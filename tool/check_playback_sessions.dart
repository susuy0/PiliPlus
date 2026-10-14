// Standalone lifecycle regressions, using the same helpers as the real player.
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/playback_session.dart';
import 'package:PiliPlus/pages/video/vertical_feed/playback_commands.dart';
import 'package:PiliPlus/pages/video/vertical_feed/video_geometry.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  var passed = 0;
  Future<void> run(String name, Future<void> Function() test) async {
    await test();
    passed++;
    print('PASS $name');
  }

  await run('an old queued seek cannot move the next media', () async {
    final session = PlaybackSession(), commands = PlaybackCommands();
    final gate = Completer<void>();
    final blocker = commands.run(() => gate.future);
    final old = session.beginSeek();
    var oldExecuted = false;
    final pending = commands.run(() async {
      if (session.accepts(old)) oldExecuted = true;
    });
    session.changeMedia();
    gate.complete();
    await blocker;
    await pending;
    check(!oldExecuted, 'old seek reached new media');
  });
  await run('cancelled and superseded seeks never regain ownership', () async {
    final session = PlaybackSession();
    final old = session.beginSeek(), latest = session.beginSeek();
    check(
      !session.accepts(old) && session.accepts(latest),
      'seek ordering failed',
    );
    session.cancelSeek();
    check(!session.accepts(latest), 'cancelled seek accepted');
  });
  await run(
    'rapid hold and release restores rate even before native start',
    () async {
      var rate = 1.0;
      final applied = <double>[];
      final controller = TemporaryPlaybackRate(
        apply: (value) async {
          rate = value;
        },
        onApplied: applied.add,
      );
      final begin = controller.begin(1, 3), end = controller.end();
      await begin;
      await end;
      check(
        rate == 1 && applied.last == 1 && controller.restoreSpeed == null,
        'release lost',
      );
    },
  );
  await run('an in-flight hold cannot overwrite the release state', () async {
    var rate = 1.0;
    final applied = <double>[],
        started = Completer<void>(),
        gate = Completer<void>();
    final controller = TemporaryPlaybackRate(
      apply: (value) async {
        if (value == 3) {
          started.complete();
          await gate.future;
        }
        rate = value;
      },
      onApplied: applied.add,
    );
    final begin = controller.begin(1, 3);
    await started.future;
    final end = controller.end();
    gate.complete();
    await begin;
    await end;
    check(
      rate == 1 && applied.join(',') == '1.0',
      'stale completion changed UI speed',
    );
  });
  await run('media replacement discards queued temporary speed', () async {
    final rates = <double>[];
    final controller = TemporaryPlaybackRate(
      apply: (value) async {
        rates.add(value);
      },
      onApplied: (_) {},
    );
    final old = controller.begin(1, 3);
    controller.invalidate();
    final normal = controller.set(1);
    await old;
    await normal;
    check(rates.join(',') == '1.0', 'old speed leaked');
  });
  await run('failed speed changes do not block a later restore', () async {
    var rate = 1.0;
    final controller = TemporaryPlaybackRate(
      apply: (value) async {
        if (value == 3) throw StateError('native failure');
        rate = value;
      },
      onApplied: (_) {},
    );
    try {
      await controller.begin(1, 3);
    } catch (_) {}
    await controller.end();
    check(rate == 1, 'restore queue blocked');
  });
  await run('a static scene with new native frames is never a stall', () async {
    final detector = VideoFrameStall();
    for (var i = 0; i < 20; i++) {
      check(
        !detector.sample(
          nowMs: i * 1000,
          positionMs: i * 1000,
          frameSerial: i + 1,
          eligible: true,
        ),
        'static scene falsely recovered',
      );
    }
  });
  await run(
    'stalled texture recovery is bounded and respects cooldown',
    () async {
      final detector = VideoFrameStall();
      bool sample(int ms) => detector.sample(
        nowMs: ms,
        positionMs: ms,
        frameSerial: 1,
        eligible: true,
      );
      check(!sample(0) && !sample(3000) && sample(4000), 'stall not detected');
      check(
        !sample(5000) && !sample(10000) && sample(35000),
        'cooldown broken',
      );
      check(!sample(36000) && !sample(70000), 'unbounded recovery');
      detector.reset(mediaChanged: true);
      check(!sample(71000) && sample(76000), 'new media cannot recover');
    },
  );
  await run(
    'pause, buffering and unavailable frame counters do not recover',
    () async {
      final detector = VideoFrameStall();
      for (var i = 0; i < 15; i++) {
        check(
          !detector.sample(
            nowMs: i * 1000,
            positionMs: i * 1000,
            frameSerial: i % 2 == 0 ? null : 1,
            eligible: false,
          ),
          'idle recovery',
        );
      }
      check(
        !detector.sample(
          nowMs: 20000,
          positionMs: 1000,
          frameSerial: 1,
          eligible: true,
        ),
        'start',
      );
      check(
        !detector.sample(
          nowMs: 30000,
          positionMs: 1000,
          frameSerial: 1,
          eligible: true,
        ),
        'paused clock',
      );
    },
  );
  await run(
    'horizontal danmaku bounds exclude top and bottom black bars',
    () async {
      final bounds = feedVideoBounds(
        393,
        600,
        mediaWidth: 1920,
        mediaHeight: 1080,
      );
      check(
        bounds.width == 393 &&
            bounds.top > 180 &&
            bounds.height < 222 &&
            (bounds.top * 2 + bounds.height - 600).abs() < .01,
        'wrong horizontal bounds',
      );
    },
  );
  await run(
    'portrait and unknown dimensions have finite contained bounds',
    () async {
      final portrait = feedVideoBounds(
        393,
        600,
        mediaWidth: 1080,
        mediaHeight: 1920,
      );
      final unknown = feedVideoBounds(393, 600, mediaWidth: 0, mediaHeight: 0);
      check(portrait.height == 600 && portrait.left > 0, 'portrait bounds');
      check(unknown.width == 393 && unknown.height == 600, 'unknown bounds');
    },
  );
  print('$passed playback session checks passed');
}

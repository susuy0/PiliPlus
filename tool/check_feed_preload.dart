// Standalone resource/lifecycle checks; no Flutter bootstrap or video network.
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:PiliPlus/pages/video/vertical_feed/preloader.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

class Resource {
  Resource() {
    live++;
    if (live > peak) peak = live;
  }
  static int live = 0;
  static int peak = 0;
  bool disposed = false;
  Future<void> close() async {
    check(!disposed, 'resource was released twice');
    disposed = true;
    live--;
  }
}

Future<void> main() async {
  var checks = 0;
  Future<void> run(String name, Future<void> Function() test) async {
    Resource.live = Resource.peak = 0;
    await test();
    check(Resource.live == 0, 'leaked standby after $name');
    checks++;
    print('PASS $name');
  }

  NextVideoPreloader<Resource> pool({
    Duration ttl = const Duration(minutes: 5),
  }) => NextVideoPreloader(release: (value) => value.close(), ttl: ttl);

  await run(
    'matching playback takes the buffered resource without reopening it',
    () async {
      final p = pool();
      var opens = 0;
      await p.prepare('video/audio/codec', (_) async {
        opens++;
        return Resource();
      });
      final active = p.take('video/audio/codec');
      check(
        active != null && !active.disposed && opens == 1,
        'buffer was not adopted',
      );
      await p.dispose();
      check(!active!.disposed, 'disposing standby released active playback');
      await active.close();
    },
  );
  await run('duplicate preparation shares one pending load', () async {
    final p = pool();
    final started = Completer<void>();
    final complete = Completer<Resource>();
    var opens = 0;
    final first = p.prepare('next', (_) {
      opens++;
      started.complete();
      return complete.future;
    });
    await started.future;
    final second = p.prepare('next', (_) async {
      opens++;
      return Resource();
    });
    check(identical(first, second), 'pending load was duplicated');
    complete.complete(Resource());
    check(
      await first && await second && opens == 1,
      'duplicate native allocation',
    );
    await p.dispose();
  });
  await run(
    'rapid turns release stale loads before creating the newest standby',
    () async {
      final p = pool();
      final started = Completer<void>();
      final complete = Completer<Resource>();
      final old = p.prepare('old', (_) {
        started.complete();
        return complete.future;
      });
      await started.future;
      final newest = p.prepare('new', (_) async => Resource());
      complete.complete(Resource());
      check(
        !await old && await newest && Resource.peak == 1,
        'overlapping standby allocations',
      );
      check(
        p.take('old') == null && p.has('new'),
        'stale playback was selected',
      );
      await p.dispose();
    },
  );
  await run(
    'audio, codec and URL mismatches keep normal playback available',
    () async {
      final p = pool();
      await p.prepare('url/audioA/codecA', (_) async => Resource());
      check(p.take('url/audioB/codecA') == null, 'wrong audio adopted');
      check(p.take('url/audioA/codecB') == null, 'wrong codec adopted');
      check(p.has('url/audioA/codecA'), 'mismatch damaged ready resource');
      await p.dispose();
    },
  );
  await run(
    'background or memory cancellation rejects late completion',
    () async {
      final p = pool();
      final started = Completer<void>();
      final complete = Completer<Resource>();
      final task = p.prepare('next', (_) {
        started.complete();
        return complete.future;
      });
      await started.future;
      p.cancel();
      complete.complete(Resource());
      check(
        !await task && !p.has('next'),
        'background preload survived cancellation',
      );
      await p.dispose();
    },
  );
  await run(
    'failed preload can retry and never prevents foreground fallback',
    () async {
      final p = pool();
      check(
        !await p.prepare('next', (_) async => throw StateError('network')),
        'error treated as ready',
      );
      check(p.take('next') == null, 'failed source was adopted');
      check(
        await p.prepare('next', (_) async => Resource()),
        'retry did not recover',
      );
      await p.dispose();
    },
  );
  await run(
    'expired and disposed standby resources are released exactly once',
    () async {
      final p = pool(ttl: const Duration(milliseconds: 10));
      await p.prepare('next', (_) async => Resource());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      check(
        !p.has('next') && p.take('next') == null,
        'expired source was used',
      );
      await p.dispose();
      check(
        !await p.prepare('after-exit', (_) async => Resource()),
        'allocated after disposal',
      );
    },
  );
  print('$checks preload checks passed.');
}

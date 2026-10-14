// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/pages/video/vertical_feed/media_cache.dart';
import 'package:PiliPlus/pages/video/vertical_feed/playback_commands.dart';
import 'package:PiliPlus/pages/video/vertical_feed/preloader.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> fails(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (_) {
    return;
  }
  throw StateError('expected failure');
}

Uint8List movie({
  int version = 0,
  int fragmentBytes = 100,
  int count = 4,
  int gap = 0,
}) {
  final sidxSize = (version == 0 ? 32 : 40) + count * 12;
  final headerSize = 16 + sidxSize;
  final bytes = Uint8List(headerSize + gap + count * 100);
  final d = ByteData.sublistView(bytes);
  d.setUint32(0, 16);
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  d.setUint32(16, sidxSize);
  bytes.setRange(20, 24, 'sidx'.codeUnits);
  d.setUint8(24, version);
  d.setUint32(28, 1);
  d.setUint32(32, 1000);
  var p = 36;
  if (version == 0) {
    d.setUint32(p + 4, gap);
    p += 8;
  } else {
    d.setUint64(p + 8, gap);
    p += 16;
  }
  d.setUint16(p + 2, count);
  p += 4;
  for (var i = 0; i < count; i++, p += 12) {
    d.setUint32(p, fragmentBytes);
    d.setUint32(p + 4, 2000);
    d.setUint32(p + 8, 0x90000000);
  }
  for (var i = headerSize; i < bytes.length; i++) {
    bytes[i] = i % 251;
  }
  return bytes;
}

int headEnd(Uint8List bytes) => 15 + ByteData.sublistView(bytes).getUint32(16);

class Origin {
  Origin(this.server, this.bytes);
  final HttpServer server;
  final Uint8List bytes;
  final ranges = <String>[];
  bool ignoreRange = false;
  int? declaredTotal;
  Completer<void>? hold;
  static Future<Origin> create(Uint8List bytes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = Origin(server, bytes);
    server.listen((r) async {
      try {
        final range = r.headers.value(HttpHeaders.rangeHeader)!;
        origin.ranges.add(range);
        check(
          r.headers.value(HttpHeaders.refererHeader) ==
              'https://www.bilibili.com',
          'missing CDN referer',
        );
        check(
          r.headers.value(HttpHeaders.userAgentHeader) == 'test-player',
          'missing CDN user agent',
        );
        await origin.hold?.future;
        final parts = range.substring(6).split('-').map(int.parse).toList();
        final start = parts[0], end = parts[1];
        r.response.statusCode = origin.ignoreRange ? 200 : 206;
        r.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${origin.declaredTotal ?? bytes.length}',
        );
        r.response.contentLength = end - start + 1;
        r.response.add(bytes.sublist(start, end + 1));
        await r.response.close();
      } catch (_) {
        await r.response.close().catchError((Object _) {});
      }
    });
    return origin;
  }

  String get url => 'http://127.0.0.1:${server.port}/video.mp4';
  FeedCacheTrack get track =>
      FeedCacheTrack(url: url, indexEnd: headEnd(bytes));
  Future<void> close() async {
    if (hold?.isCompleted == false) hold!.complete();
    await server.close(force: true);
  }
}

FeedMediaCache cache() => FeedMediaCache(
  userAgent: 'test-player',
  referer: 'https://www.bilibili.com',
);
Future<({int status, List<int> bytes, String? range})> get(
  String url, {
  String? range,
  String method = 'GET',
}) async {
  final c = HttpClient();
  try {
    final r = await c.openUrl(method, Uri.parse(url));
    if (range != null) r.headers.set(HttpHeaders.rangeHeader, range);
    final response = await r.close();
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (
      status: response.statusCode,
      bytes: body,
      range: response.headers.value(HttpHeaders.contentRangeHeader),
    );
  } finally {
    c.close(force: true);
  }
}

bool same(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

Future<void> main() async {
  var passed = 0;
  Future<void> run(String name, Future<void> Function() body) async {
    await body();
    passed++;
    print('PASS $name');
  }

  await run(
    'sidx versions, offsets and whole fragments cover the first three seconds',
    () async {
      for (final version in [0, 1]) {
        final bytes = movie(version: version, gap: 7);
        final plan = FeedPrefixPlan.parse(bytes.sublist(0, headEnd(bytes) + 1));
        check(
          plan.end == headEnd(bytes) + 7 + 200 &&
              plan.duration == const Duration(seconds: 4),
          'wrong prefix coverage',
        );
      }
      final short = movie(count: 1);
      check(
        FeedPrefixPlan.parse(short.sublist(0, headEnd(short) + 1)).duration ==
            const Duration(seconds: 2),
        'short clip not complete',
      );
      final bad = movie();
      ByteData.sublistView(bad).setUint32(32, 0);
      await fails(() async => FeedPrefixPlan.parse(bad));
      await fails(() async => FeedPrefixPlan.parse(Uint8List(4)));
    },
  );
  await run(
    'cached audio and video prefix reads need no new network request',
    () async {
      final video = await Origin.create(movie());
      final audio = await Origin.create(movie(version: 1));
      final c = cache();
      try {
        final warm = await c.prepare([audio.track, video.track], () => true);
        check(
          warm.duration == const Duration(seconds: 4),
          'audio/video duration mismatch',
        );
        final urls = await c.activate(warm);
        final before = video.ranges.length + audio.ranges.length;
        for (final o in [video, audio]) {
          final result = await get(
            urls[o.url]!,
            range: 'bytes=0-${headEnd(o.bytes) + 199}',
          );
          check(
            result.status == 206 &&
                same(result.bytes, o.bytes.sublist(0, headEnd(o.bytes) + 200)),
            'cached bytes changed',
          );
        }
        check(
          video.ranges.length + audio.ranges.length == before,
          'prefix reopened CDN',
        );
      } finally {
        await c.dispose();
        await video.close();
        await audio.close();
      }
    },
  );
  await run('range reads crossing the cache boundary, seeking, HEAD and suffix are exact', () async {
    final o = await Origin.create(movie());
    final c = cache();
    try {
      final warm = await c.prepare([o.track], () => true);
      final url = (await c.activate(warm))[o.url]!;
      final result = await get(url, range: 'bytes=20-${o.bytes.length - 1}');
      check(
        result.status == 206 && same(result.bytes, o.bytes.sublist(20)),
        'mixed range corrupted',
      );
      final suffix = await get(url, range: 'bytes=-40');
      check(
        same(suffix.bytes, o.bytes.sublist(o.bytes.length - 40)),
        'suffix corrupted',
      );
      check((await get(url, method: 'HEAD')).bytes.isEmpty, 'HEAD sent body');
      check(
        (await get(url, range: 'bytes=999999-')).status == 416,
        'invalid seek accepted',
      );
      check(
        (await get(url, range: 'bytes=0-1,2-3')).status == 416,
        'unsupported multi-range accepted',
      );
      final whole = await get(url);
      check(
        whole.status == 200 && same(whole.bytes, o.bytes),
        'whole-file stream corrupted',
      );
    } finally {
      await c.dispose();
      await o.close();
    }
  });
  await run(
    'cancelled and unready preloads cannot delay foreground playback',
    () async {
      final o = await Origin.create(movie());
      final c = cache();
      final p = NextVideoPreloader<FeedCachedMedia>(release: c.release);
      var current = true;
      o.hold = Completer<void>();
      try {
        final loading = p.prepare(
          'slow',
          (_) => c.prepare([o.track], () => current),
        );
        while (o.ranges.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        check(p.take('slow') == null, 'unready cache was adopted');
        current = false;
        p.cancel();
        c.cancelPending();
        check(
          !await loading.timeout(const Duration(seconds: 1)),
          'cancelled cache became ready',
        );
      } finally {
        await o.close();
        await p.dispose();
        await c.dispose();
      }
    },
  );
  await run('ignored ranges and oversized media prefixes fall back before downloading payload', () async {
    final o = await Origin.create(movie());
    final c = cache();
    try {
      o.ignoreRange = true;
      await fails(() => c.prepare([o.track], () => true));
      o.ignoreRange = false;
      final large = await Origin.create(
        movie(fragmentBytes: FeedMediaCache.maxBytes),
      );
      large.declaredTotal = FeedMediaCache.maxBytes * 8;
      try {
        await fails(() => c.prepare([large.track], () => true));
        check(large.ranges.length == 1, 'oversized payload fetched');
      } finally {
        await large.close();
      }
    } finally {
      await c.dispose();
      await o.close();
    }
  });
  await run(
    'active prefix survives pool disposal and old playback routes retire',
    () async {
      final o = await Origin.create(movie());
      final c = cache();
      final p = NextVideoPreloader<FeedCachedMedia>(release: c.release);
      try {
        await p.prepare('first', (current) => c.prepare([o.track], current));
        final first = (await c.activate(p.take('first')!))[o.url]!;
        await p.dispose();
        check(
          (await get(first, range: 'bytes=0-15')).status == 206,
          'pool disposed active media',
        );
        final next = (await c.activate(
          await c.prepare([o.track], () => true),
        ))[o.url]!;
        c.retain({next});
        check((await get(first)).status == 404, 'old route retained');
        check(
          (await get(next, range: 'bytes=0-15')).status == 206,
          'new route lost',
        );
      } finally {
        await p.dispose();
        await c.dispose();
        await o.close();
      }
    },
  );
  await run('late pause completes before play and failed commands do not block later playback', () async {
    final queue = PlaybackCommands();
    final stopped = Completer<void>();
    final events = <String>[];
    final pause = queue.run(() async {
      events.add('pause-start');
      await stopped.future;
      events.add('pause-end');
    });
    final play = queue.run(() async {
      events.add('session-active');
      events.add('play');
      return true;
    });
    await Future<void>.delayed(Duration.zero);
    check(events.join(',') == 'pause-start', 'play overtook old pause');
    stopped.complete();
    await pause;
    check(await play, 'generic activation result lost');
    check(
      events.join(',') == 'pause-start,pause-end,session-active,play',
      'incorrect playback order',
    );
    await fails(
      () => queue.run(() async {
        throw StateError('native failure');
      }),
    );
    await queue.run(() async {
      events.add('recovered');
    });
    check(events.last == 'recovered', 'command queue remained broken');
  });
  await run(
    'page remounts never cancel the active audio-session volume listener',
    () async {
      final life = PlaybackListenerLifetime();
      var attaches = 0, cancels = 0;
      for (var page = 0; page < 20; page++) {
        life.ensureAttached(() {
          attaches++;
        });
      }
      check(attaches == 1 && cancels == 0, 'page turn replaced audio listener');
      life.dispose(() {
        cancels++;
      });
      life.dispose(() {
        cancels++;
      });
      life.ensureAttached(() {
        attaches++;
      });
      check(
        attaches == 1 && cancels == 1,
        'closed player reused or double-cancelled listener',
      );
      final retry = PlaybackListenerLifetime();
      await fails(() async {
        retry.ensureAttached(() {
          throw StateError('plugin unavailable');
        });
        return null;
      });
      retry.ensureAttached(() {
        attaches++;
      });
      retry.dispose(() {
        cancels++;
      });
      check(attaches == 2 && cancels == 2, 'failed attachment could not retry');
    },
  );
  print('$passed media-cache/playback checks passed.');
}

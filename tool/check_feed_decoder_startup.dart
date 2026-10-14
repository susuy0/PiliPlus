// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/pages/video/vertical_feed/media_cache.dart';

import 'check_feed_media_cache.dart' as fixture;

int indexEnd(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    final size = data.getUint32(offset);
    if (size < 8 || offset + size > bytes.length) break;
    if (String.fromCharCodes(bytes.sublist(offset + 4, offset + 8)) == 'sidx') {
      return offset + size - 1;
    }
    offset += size;
  }
  throw StateError('generated fixture has no sidx');
}

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('feed-decoder-');
  final cache = fixture.cache();
  fixture.Origin? video;
  fixture.Origin? audio;
  Process? decoder;
  StreamSubscription<List<int>>? output;
  try {
    Future<void> generate(String name, List<String> options) async {
      final result = await Process.run('ffmpeg', [
        '-y',
        '-v',
        'error',
        ...options,
        '-t',
        '40',
        '-movflags',
        '+dash+global_sidx',
        '-frag_duration',
        '1000000',
        '${dir.path}/$name.mp4',
      ]);
      fixture.check(
        result.exitCode == 0,
        'fixture generation failed: ${result.stderr}',
      );
    }

    await generate('video', [
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=320x180:rate=30',
      '-an',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-g',
      '30',
    ]);
    await generate('audio', [
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000',
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      '96k',
    ]);
    final vb = await File('${dir.path}/video.mp4').readAsBytes();
    final ab = await File('${dir.path}/audio.mp4').readAsBytes();
    video = await fixture.Origin.create(vb);
    audio = await fixture.Origin.create(ab);
    final warm = await cache.prepare([
      FeedCacheTrack(url: audio.url, indexEnd: indexEnd(ab)),
      FeedCacheTrack(url: video.url, indexEnd: indexEnd(vb)),
    ], () => true);
    final urls = await cache.activate(warm);
    // Any unprepared CDN read is now blocked. The output must still produce a
    // first decoded RGB frame promptly and contain all 90 frames of the 3s clip.
    video.hold = Completer<void>();
    audio.hold = Completer<void>();
    final clock = Stopwatch()..start();
    decoder = await Process.start('ffmpeg', [
      '-v', 'error',
      // The app skips extra stream-info scans for a validated MP4 init segment.
      '-analyzeduration',
      '100000',
      '-probesize',
      '32768',
      '-i',
      urls[video.url]!,
      '-analyzeduration',
      '100000',
      '-probesize',
      '32768',
      '-i',
      urls[audio.url]!,
      '-map', '0:v', '-t', '3', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-',
    ]);
    var firstFrameMs = -1;
    var decodedBytes = 0;
    final drained = Completer<void>();
    output = decoder.stdout.listen((chunk) {
      decodedBytes += chunk.length;
      if (decodedBytes >= 320 * 180 * 3 && firstFrameMs < 0) {
        firstFrameMs = clock.elapsedMilliseconds;
      }
    }, onDone: drained.complete);
    final errors = decoder.stderr.drain<void>();
    final code = await decoder.exitCode.timeout(const Duration(seconds: 15));
    await drained.future;
    await errors;
    fixture.check(code == 0, 'cached decoder failed');
    fixture.check(
      firstFrameMs >= 0 && firstFrameMs < 1500,
      'first frame waited for blocked CDN: ${firstFrameMs}ms',
    );
    fixture.check(
      decodedBytes == 90 * 320 * 180 * 3,
      'incomplete three-second video',
    );
    print(
      'PASS actual H264/AAC MP4 startup with stalled CDN: first RGB frame ${firstFrameMs}ms, 90 decoded frames',
    );
  } finally {
    decoder?.kill();
    await output?.cancel();
    await cache.dispose();
    await video?.close();
    await audio?.close();
    await dir.delete(recursive: true);
  }
}

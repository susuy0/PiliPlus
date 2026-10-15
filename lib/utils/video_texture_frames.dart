import 'dart:io';

import 'package:PiliPlus/utils/ios/pip_helper.dart';
import 'package:flutter/services.dart';

/// Native texture submissions, independent of mpv's advancing playback clock.
abstract final class VideoTextureFrames {
  static const _mac = MethodChannel('com.example.piliplus/video_frames');

  static Future<int?> serial(int textureId) async {
    if (Platform.isIOS) return IOSPipHelper.frameSerial(textureId);
    if (!Platform.isMacOS) return null;
    try {
      return await _mac
          .invokeMethod<int>('frameSerial', {'textureId': textureId})
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // Unavailable counters must never trigger recovery or block playback.
      return null;
    }
  }
}

import 'dart:async';

import 'package:PiliPlus/pages/video/vertical_feed/playback_commands.dart';

/// A pending seek belongs to one media and one user request.
class PlaybackSession {
  int _media = 0;
  int _seek = 0;
  int get media => _media;
  void changeMedia() {
    _media++;
    _seek++;
  }

  void cancelSeek() => _seek++;
  ({int media, int seek}) beginSeek() => (media: _media, seek: ++_seek);
  bool accepts(({int media, int seek}) request) =>
      request.media == _media && request.seek == _seek;
}

/// Always queue the release, even when the native rate still looks unchanged.
/// An old command completion must not overwrite the latest requested speed.
class TemporaryPlaybackRate {
  TemporaryPlaybackRate({required this.apply, required this.onApplied});
  final Future<void> Function(double) apply;
  final void Function(double) onApplied;
  final _commands = PlaybackCommands();
  int _request = 0;
  double? restoreSpeed;

  void invalidate() {
    _request++;
    restoreSpeed = null;
  }

  Future<void> set(double speed) {
    if (!speed.isFinite || speed <= 0) return Future<void>.value();
    final request = ++_request;
    return _commands.run(() async {
      if (request != _request) return;
      await apply(speed);
      if (request == _request) onApplied(speed);
    });
  }

  Future<void> begin(double normal, double temporary) {
    restoreSpeed ??= normal;
    return set(temporary);
  }

  Future<void> end() {
    final speed = restoreSpeed;
    restoreSpeed = null;
    return speed == null ? Future<void>.value() : set(speed);
  }
}

/// Detect a stalled rendered frame counter while the playback clock keeps advancing.
/// Pauses, buffering, seeks, and unavailable frame counters are not stalls.
class VideoFrameStall {
  int? _frameSerial, _positionMs, _changedAt;
  int? _recoveredAt;
  int _recoveries = 0;
  void reset({bool mediaChanged = false}) {
    _frameSerial = _positionMs = _changedAt = null;
    if (mediaChanged) {
      _recoveredAt = null;
      _recoveries = 0;
    }
  }

  bool sample({
    required int nowMs,
    required int positionMs,
    required int? frameSerial,
    required bool eligible,
  }) {
    if (!eligible || frameSerial == null) {
      reset();
      return false;
    }
    if (_frameSerial == null ||
        frameSerial != _frameSerial ||
        positionMs < (_positionMs ?? positionMs)) {
      _frameSerial = frameSerial;
      _positionMs = positionMs;
      _changedAt = nowMs;
      return false;
    }
    if (nowMs - _changedAt! < 4000 ||
        positionMs - _positionMs! < 2000 ||
        _recoveries >= 2 ||
        (_recoveredAt != null && nowMs - _recoveredAt! < 30000))
      return false;
    _recoveries++;
    _recoveredAt = nowMs;
    reset();
    return true;
  }
}

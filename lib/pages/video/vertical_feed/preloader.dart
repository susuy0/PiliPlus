import 'dart:async';

/// Require media packets for the first three seconds, not merely a nonzero
/// buffer notification. A shorter clip is ready when its complete cache exists.
abstract final class FeedPreloadPolicy {
  static const target = Duration(seconds: 3);
  static bool ready(
    Duration buffer,
    Duration duration, {
    bool eof = false,
    Duration target = const Duration(seconds: 3),
  }) =>
      buffer >= target ||
      (duration > Duration.zero &&
          duration <= target &&
          (buffer >= duration || (eof && buffer > Duration.zero)));
}

/// Serializes one silent standby resource. A stale load is released before the
/// next is created; only an exact, unexpired key may be handed to playback.
class NextVideoPreloader<T> {
  NextVideoPreloader({
    required this.release,
    this.ttl = const Duration(minutes: 5),
  });
  final Future<void> Function(T value) release;
  final Duration ttl;
  Future<void> _serial = Future<void>.value();
  ({String key, T value, DateTime expires})? _ready;
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
  String? _pendingKey;
  Future<bool>? _pending;

  bool has(String key) =>
      !_disposed &&
      _ready?.key == key &&
      DateTime.now().isBefore(_ready!.expires);
  bool targets(String key) => _ready?.key == key || _pendingKey == key;

  Future<bool> prepare(
    String key,
    Future<T> Function(bool Function() current) load,
  ) {
    if (_disposed) return Future<bool>.value(false);
    if (has(key)) return Future<bool>.value(true);
    if (_pendingKey == key && _pending != null) return _pending!;
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    final task = _serial.then((_) async {
      if (!current()) return false;
      await _releaseReady();
      if (!current()) return false;
      T value;
      try {
        value = await load(current);
      } catch (_) {
        return false;
      }
      if (!current()) {
        await release(value);
        return false;
      }
      _ready = (key: key, value: value, expires: DateTime.now().add(ttl));
      _expiry = Timer(ttl, cancel);
      return true;
    });
    _pendingKey = key;
    _pending = task.whenComplete(() {
      if (generation == _generation) {
        _pendingKey = null;
        _pending = null;
      }
    });
    _serial = task.then<void>((_) {}).catchError((Object _) {});
    return _pending!;
  }

  T? take(String key) {
    if (!has(key)) return null;
    final value = _ready!.value;
    _ready = null;
    _expiry?.cancel();
    _expiry = null;
    _generation++;
    _pendingKey = null;
    _pending = null;
    return value;
  }

  Future<T?> takeWhenReady(
    String key, {
    Duration patience = const Duration(milliseconds: 350),
  }) async {
    if (has(key)) return take(key);
    final pending = _pendingKey == key ? _pending : null;
    if (pending == null) return null;
    try {
      await pending.timeout(patience);
    } catch (_) {
      return null;
    }
    return take(key);
  }

  Future<void> _releaseReady() async {
    _expiry?.cancel();
    _expiry = null;
    final ready = _ready;
    _ready = null;
    if (ready != null) await release(ready.value);
  }

  void cancel() {
    _generation++;
    _pendingKey = null;
    _pending = null;
    _serial = _serial.then((_) => _releaseReady()).catchError((Object _) {});
  }

  Future<void> dispose() async {
    _disposed = true;
    cancel();
    await _serial;
  }
}

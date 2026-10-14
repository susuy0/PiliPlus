import 'dart:async';

/// A pause must finish before a later play can start the same native player.
class PlaybackCommands {
  Future<void> _tail = Future<void>.value();
  Future<T> run<T>(Future<T> Function() command) {
    final result = _tail.then((_) => command());
    _tail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }
}

/// Shared-player listeners outlive individual video widgets and page turns.
class PlaybackListenerLifetime {
  bool _attached = false;
  bool _closed = false;
  void ensureAttached(void Function() attach) {
    if (_closed || _attached) return;
    attach();
    _attached = true;
  }

  void dispose(void Function() cancel) {
    if (_closed) return;
    _closed = true;
    if (_attached) {
      _attached = false;
      cancel();
    }
  }
}

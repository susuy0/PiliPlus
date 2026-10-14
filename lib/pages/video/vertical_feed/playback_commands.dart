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

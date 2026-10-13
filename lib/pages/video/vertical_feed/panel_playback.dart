/// Playback is restored only when this panel caused the pause. A video that
/// was already paused must remain paused after collapsing comments.
enum PanelPlaybackAction { none, pause, resume }

class PanelPlaybackPolicy {
  bool _paused = false;
  bool _resume = false;
  PanelPlaybackAction update({required bool obscured, required bool playing}) {
    if (obscured && !_paused) {
      _paused = true;
      _resume = playing;
      return playing ? PanelPlaybackAction.pause : PanelPlaybackAction.none;
    }
    if (!obscured && _paused) {
      _paused = false;
      final resume = _resume;
      _resume = false;
      return resume ? PanelPlaybackAction.resume : PanelPlaybackAction.none;
    }
    return PanelPlaybackAction.none;
  }
}

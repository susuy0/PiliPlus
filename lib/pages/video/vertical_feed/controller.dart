import 'dart:collection';

typedef FeedPageLoader<T> = Future<List<T>> Function(int page);

class FeedExhausted implements Exception {
  const FeedExhausted();
}

/// Owns pagination and a bounded history; playback belongs to the video page.
class VerticalFeedController<T> {
  VerticalFeedController({
    required T seed,
    required this.loadPage,
    required this.idOf,
    this.onChanged,
  }) : items = [seed] {
    _seen.add(idOf(seed));
  }

  final FeedPageLoader<T> loadPage;
  final int Function(T) idOf;
  void Function()? onChanged;
  final List<T> items;
  final LinkedHashSet<int> _seen = LinkedHashSet();
  int index = 0;
  int _nextPage = 1;
  bool _disposed = false;
  Future<void>? _pending;
  bool get loading => _pending != null;
  String? error;
  bool ended = false;

  Future<void> loadMore() {
    if (_disposed || ended) return Future<void>.value();
    if (_pending case final pending?) return pending;
    _pending = _loadMore().whenComplete(() {
      _pending = null;
      if (!_disposed) onChanged?.call();
    });
    onChanged?.call();
    return _pending!;
  }

  Future<void> _loadMore() async {
    error = null;
    // A filtered/duplicate batch must not stop the feed or spin indefinitely.
    try {
      for (var attempt = 0; attempt < 3 && !_disposed; attempt++) {
        final batch = await loadPage(_nextPage);
        if (_disposed) return;
        _nextPage++;
        final previousLength = items.length;
        for (final item in batch) {
          if (_seen.add(idOf(item))) items.add(item);
        }
        while (_seen.length > 2048) {
          _seen.remove(_seen.first);
        }
        if (items.length > previousLength) {
          onChanged?.call();
          return;
        }
      }
      if (!_disposed) error = '暂时没有更多视频，点击重试';
    } on FeedExhausted {
      if (!_disposed) {
        ended = true;
        error = '已看完该UP主的视频';
      }
    } catch (_) {
      if (!_disposed) error = '推荐加载失败，点击重试';
    }
  }

  /// Call only after a page settles. Keep 20 previous videos and future items.
  int trimHistory() {
    if (items.length <= 100 || index <= 20) return 0;
    final removeCount = index - 20;
    items.removeRange(0, removeCount);
    index -= removeCount;
    return removeCount;
  }

  void dispose() {
    _disposed = true;
    onChanged = null;
  }
}

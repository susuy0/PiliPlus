import 'package:PiliPlus/pages/video/vertical_feed/controller.dart';

/// The UP archive endpoint uses archive/cursor pagination, not Story page IDs.
class AuthorFeedPage<T> {
  const AuthorFeedPage({
    required this.items,
    required this.aid,
    this.next,
    required this.hasNext,
  });
  final List<T> items;
  final String? aid;
  final int? next;
  final bool hasNext;
}

class AuthorFeedSource<T> {
  AuthorFeedSource({required this.fetch, String? afterAid}) : _aid = afterAid;
  final Future<AuthorFeedPage<T>> Function(String? aid, int? next) fetch;
  String? _aid;
  int? _next;
  bool _ended = false;

  Future<List<T>> call(int page) async {
    if (_ended) throw const FeedExhausted();
    final response = await fetch(_aid, _next);
    final advanced = response.aid != _aid || response.next != _next;
    _ended = !response.hasNext || !advanced;
    _aid = response.aid;
    _next = response.next;
    return response.items;
  }
}

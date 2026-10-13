// ignore_for_file: avoid_print
import 'package:PiliPlus/pages/video/vertical_feed/author_source.dart';
import 'package:PiliPlus/pages/video/vertical_feed/controller.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final allUploads = AuthorFeedSource<int>(
    fetch: (aid, next) async {
      check(aid == null, 'oldest-video entry skipped newer UP uploads');
      return const AuthorFeedPage(items: [5, 4, 3], aid: '3', hasNext: false);
    },
  );
  final oldest = VerticalFeedController<int>(
    seed: 3,
    loadPage: allUploads.call,
    idOf: (id) => id,
  );
  await oldest.loadMore();
  check(
    oldest.items.join(',') == '3,5,4',
    'UP feed omitted newer videos or duplicated the clicked video',
  );
  oldest.dispose();
  print('PASS entering an old UP video retains newer uploads');
  final calls = <String?>[];
  var fail = true;
  final source = AuthorFeedSource<int>(
    afterAid: '100',
    fetch: (aid, next) async {
      calls.add(aid);
      if (fail) {
        fail = false;
        throw StateError('network');
      }
      return aid == '100'
          ? const AuthorFeedPage(
              items: [100, 99, 98],
              aid: '98',
              next: 2,
              hasNext: true,
            )
          : const AuthorFeedPage(items: [97], aid: '97', hasNext: false);
    },
  );
  final feed = VerticalFeedController<int>(
    seed: 100,
    loadPage: source.call,
    idOf: (id) => id,
  );
  await feed.loadMore();
  check(
    feed.items.length == 1 && feed.error != null,
    'failed request damaged current video',
  );
  await feed.loadMore();
  check(calls[0] == '100' && calls[1] == '100', 'retry advanced the UP cursor');
  check(
    feed.items.join(',') == '100,99,98',
    'seed was duplicated or archive order changed',
  );
  feed.index = 1;
  await feed.loadMore();
  check(
    feed.items.last == 97 && calls.last == '98',
    'next UP page did not use archive cursor',
  );
  await feed.loadMore();
  final count = calls.length;
  await feed.loadMore();
  check(
    feed.ended && calls.length == count && feed.index == 1,
    'exhaustion looped or lost current index',
  );
  feed.dispose();
  print('PASS UP cursor retry, seed deduplication, pagination and exhaustion');

  var requests = 0;
  final filtered = AuthorFeedSource<int>(
    fetch: (aid, next) async {
      requests++;
      return requests == 1
          ? const AuthorFeedPage(items: [], aid: '9', hasNext: true)
          : const AuthorFeedPage(items: [8], aid: '8', hasNext: false);
    },
  );
  final next = VerticalFeedController<int>(
    seed: 10,
    loadPage: filtered.call,
    idOf: (id) => id,
  );
  await next.loadMore();
  check(
    next.items.join(',') == '10,8' && requests == 2,
    'filtered UP page stopped later archives',
  );
  next.dispose();
  print(
    'PASS filtered UP pages continue without introducing recommendation items',
  );

  final stalled = AuthorFeedSource<int>(
    afterAid: '5',
    fetch: (aid, next) async =>
        const AuthorFeedPage(items: [5], aid: '5', hasNext: true),
  );
  await stalled.call(1);
  try {
    await stalled.call(2);
    throw StateError('stalled cursor was requested again');
  } on FeedExhausted {
    print('PASS repeated UP cursor terminates safely');
  }
}

// Standalone: dart tool/check_vertical_feed.dart
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:PiliPlus/pages/video/vertical_feed/controller.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  var checks = 0;
  Future<void> run(String name, Future<void> Function() test) async {
    await test();
    checks++;
    print('PASS $name');
  }

  await run('seed and duplicate archives are never appended twice', () async {
    final pages = <int>[];
    final feed = VerticalFeedController<int>(
      seed: 1,
      idOf: (id) => id,
      loadPage: (page) async {
        pages.add(page);
        return page == 1 ? [1, 2, 2, 3] : [3, 4];
      },
    );
    await feed.loadMore();
    await feed.loadMore();
    check(feed.items.join(',') == '1,2,3,4', 'Duplicate recommendation');
    check(pages.join(',') == '1,2', 'Wrong pagination cursor');
    feed.dispose();
  });

  await run(
    'simultaneous prefetch and tail requests share one request',
    () async {
      final response = Completer<List<int>>();
      var requests = 0;
      final feed = VerticalFeedController<int>(
        seed: 1,
        idOf: (id) => id,
        loadPage: (_) {
          requests++;
          return response.future;
        },
      );
      final first = feed.loadMore();
      final second = feed.loadMore();
      check(identical(first, second), 'Concurrent request was not coalesced');
      check(requests == 1 && feed.loading, 'More than one active request');
      response.complete([2]);
      await first;
      check(!feed.loading && feed.items.length == 2, 'Loading flag stuck');
      feed.dispose();
    },
  );

  await run(
    'failed requests retry the same page without losing history',
    () async {
      final pages = <int>[];
      final feed = VerticalFeedController<int>(
        seed: 1,
        idOf: (id) => id,
        loadPage: (page) async {
          pages.add(page);
          if (pages.length == 1) throw StateError('offline');
          return [2];
        },
      );
      await feed.loadMore();
      check(feed.error != null && !feed.loading, 'Missing recoverable error');
      await feed.loadMore();
      check(pages.join(',') == '1,1', 'Retry skipped the failed page');
      check(
        feed.error == null && feed.items.join(',') == '1,2',
        'Retry failed',
      );
      feed.dispose();
    },
  );

  await run(
    'duplicate-only and filtered batches do not cause an infinite loop',
    () async {
      var requests = 0;
      final feed = VerticalFeedController<int>(
        seed: 1,
        idOf: (id) => id,
        loadPage: (_) async {
          requests++;
          return [1];
        },
      );
      await feed.loadMore();
      check(
        requests == 3 && feed.error != null,
        'Unbounded empty-page retries',
      );
      check(feed.items.length == 1 && !feed.loading, 'History corrupted');
      feed.dispose();
    },
  );

  await run(
    'an empty first batch can be followed by new recommendations',
    () async {
      final feed = VerticalFeedController<int>(
        seed: 1,
        idOf: (id) => id,
        loadPage: (page) async => page == 1 ? [] : [2],
      );
      await feed.loadMore();
      check(
        feed.items.join(',') == '1,2' && feed.error == null,
        'Stopped too early',
      );
      feed.dispose();
    },
  );

  await run(
    'late responses after leaving the feed never update its state',
    () async {
      final response = Completer<List<int>>();
      var notifications = 0;
      final feed = VerticalFeedController<int>(
        seed: 1,
        idOf: (id) => id,
        loadPage: (_) => response.future,
        onChanged: () => notifications++,
      );
      final pending = feed.loadMore();
      final beforeDispose = notifications;
      feed.dispose();
      response.complete([2]);
      await pending;
      check(
        notifications == beforeDispose && feed.items.length == 1,
        'Disposed feed changed',
      );
    },
  );

  await run(
    'long sessions retain the current item and twenty previous items',
    () async {
      final feed = VerticalFeedController<int>(
        seed: 0,
        idOf: (id) => id,
        loadPage: (_) async => List.generate(140, (i) => i + 1),
      );
      await feed.loadMore();
      feed.index = 110;
      final current = feed.items[feed.index];
      final removed = feed.trimHistory();
      check(removed == 90 && feed.index == 20, 'Incorrect history trim');
      check(
        feed.items[feed.index] == current && feed.items.last == 140,
        'Active/future item lost',
      );
      feed.dispose();
    },
  );

  await run(
    'collection starts at the current episode and retains earlier episodes',
    () async {
      final source = List.generate(140, (i) => i + 1);
      final feed = VerticalFeedController<int>.fromItems(
        items: source,
        index: 110,
        idOf: (id) => id,
      );
      check(
        feed.items[feed.index] == 111,
        'Collection restarted from the first episode',
      );
      source.clear();
      check(
        feed.items.length == 140,
        'Source mutation changed the selected collection',
      );
      check(
        feed.trimHistory() == 0 && feed.items.first == 1,
        'Earlier collection episodes were trimmed',
      );
      await feed.loadMore();
      check(
        feed.ended && feed.error == '已看完该合集的视频' && feed.items.last == 140,
        'Collection appended recommendations',
      );
      feed.dispose();
    },
  );
  await run(
    'late recommendation responses cannot replace the selected collection',
    () async {
      final response = Completer<List<int>>();
      final recommendations = VerticalFeedController<int>(
        seed: 1,
        idOf: (id) => id,
        loadPage: (_) => response.future,
      );
      final pending = recommendations.loadMore();
      final collection = VerticalFeedController<int>.fromItems(
        items: [3, 1, 5],
        index: 1,
        idOf: (id) => id,
      );
      response.complete([8, 9]);
      await pending;
      check(
        collection.items.join(',') == '3,1,5' && collection.index == 1,
        'Late recommendations leaked into collection',
      );
      check(
        recommendations.items.join(',') == '1,8,9',
        'Return feed lost its pagination',
      );
      recommendations.dispose();
      collection.dispose();
    },
  );
  print('$checks queue checks passed.');
}

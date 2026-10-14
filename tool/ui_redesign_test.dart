import 'package:PiliPlus/pages/video/vertical_feed/collection_source.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/ugc_season.dart';
import 'package:PiliPlus/pages/shorts/controller.dart';
import 'package:PiliPlus/pages/sponsor_block/block_mixin.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/sponsor_block/segment_item.dart';
import 'package:media_kit/media_kit.dart' show Player;
import 'package:PiliPlus/pages/video/vertical_feed/story_layout.dart';
import 'package:PiliPlus/models/video/presentation.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/video/story.dart';
import 'package:PiliPlus/pages/video/vertical_feed/desktop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:PiliPlus/pages/video/vertical_feed/pager.dart';
import 'package:PiliPlus/pages/video/vertical_feed/progress_region.dart';
import 'package:PiliPlus/pages/video/vertical_feed/cover.dart';
import 'package:PiliPlus/pages/video/vertical_feed/video_surface.dart';
import 'package:PiliPlus/pages/video/vertical_feed/chrome.dart';
import 'package:PiliPlus/pages/video/vertical_feed/follow_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:hive_ce/hive.dart';
import 'package:get/get.dart';

import 'dart:async';

// Native UI regression checks: player lifetime, comment docking and large text.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/design_tokens.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/action_item.dart';
import 'package:PiliPlus/pages/video/vertical_feed/panel_playback.dart';
import 'package:PiliPlus/pages/video/vertical_feed/viewport.dart';
import 'package:PiliPlus/pages/video/vertical_feed/action_button.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// These layout checks read preferences but never exercise persistent storage.
class _DefaultPreferencesBox extends Fake implements Box<dynamic> {
  final _values = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values.containsKey(key) ? _values[key] : defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }
}

void main() {
  test(
    'collection preserves section order, current part and archive metadata',
    () {
      final current = StoryVideoItem(aid: 2, bvid: 'BV1xx411c7mD', cid: 222);
      final detail = VideoDetailData.fromJson({
        'owner': {'mid': 99, 'name': 'UP'},
        'ugc_season': {
          'id': 7,
          'title': '合集',
          'sections': [
            {
              'episodes': [
                {
                  'aid': 1,
                  'cid': 101,
                  'title': '第一集',
                  'arc': {
                    'pic': 'first.jpg',
                    'duration': 60,
                    'dimension': {'width': 1920, 'height': 1080},
                    'stat': {'coin': 3.0, 'reply': 4},
                  },
                },
                {'aid': 2, 'cid': 202},
                {'aid': 2, 'cid': 202},
                {'aid': 0},
              ],
            },
            {
              'episodes': [
                {'aid': 3, 'cid': 303, 'title': '第三集', 'badge': '充电专属'},
              ],
            },
          ],
        },
      });
      final result = collectionFeed(detail, current)!;
      expect(result.items.map((item) => item.aid).toList(), [1, 2, 3]);
      expect(result.index, 1);
      expect(result.items[1], same(current));
      expect(result.items[1].cid, 222);
      expect(result.items.first.owner.mid, 99);
      expect(result.items.first.duration, 60);
      expect(result.items.first.isPortraitVideo, isFalse);
      expect(result.items.first.storyStat?.coin, 3);
      expect(result.items.last.contentLabels, ['充电专属']);
    },
  );

  test(
    'incomplete collection data never substitutes an unrelated current video',
    () {
      final current = StoryVideoItem(aid: 2, bvid: 'BV1xx411c7mD', cid: 202);
      expect(collectionFeed(VideoDetailData(), current), isNull);
      expect(
        collectionFeed(
          VideoDetailData(
            ugcSeason: UgcSeason.fromJson({
              'sections': [
                {
                  'episodes': [
                    {'aid': 1, 'cid': 101},
                  ],
                },
              ],
            }),
          ),
          current,
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'collection caption is actionable and inactive cards cannot switch feeds',
    (tester) async {
      var entered = 0;
      Widget link(bool active) => MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: 240,
              child: FeedCollectionLink(
                title: '物理学照亮世界',
                onPressed: active ? () => entered++ : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(link(true));
      await tester.tap(find.text('合集 · 物理学照亮世界'));
      await tester.pump();
      expect(entered, 1);
      await tester.pumpWidget(link(false));
      await tester.tap(find.text('合集 · 物理学照亮世界'));
      expect(entered, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('Story search and warning use API card data only', () {
    final card = StoryVideoItem.tryParse({
      'card_goto': 'vertical_av',
      'param': '1',
      'argue_msg': '含AI生成内容',
      'creative_entrance': {
        'type': 6,
        'title': '搜索 · 三百斤青年',
        'jump_uri': 'bilibili://search?keyword=三百斤青年',
      },
    })!;
    expect(card.searchKeyword, '三百斤青年');
    expect(card.searchTitle, '搜索 · 三百斤青年');
    expect(card.argueMessage, '含AI生成内容');
    final plain = StoryVideoItem.tryParse({
      'card_goto': 'av',
      'param': '2',
      'title': '搜索标题不应生成推荐词',
    })!;
    expect(plain.searchKeyword, isNull);
  });

  testWidgets(
    'Story overlay never shrinks or remounts video when metadata grows',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <String>[];
      var infoHeight = 100.0;
      var clean = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return FeedStoryLayout(
                overlay: true,
                clean: clean,
                topInset: 54,
                bottomInset: 34,
                video: SizedBox(
                  key: const ValueKey('overlay-media'),
                  child: _LifetimeProbe(events: events),
                ),
                information: SizedBox(height: infoHeight),
                actions: const SizedBox(width: 56, height: 320),
                footer: const SizedBox(),
              );
            },
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const ValueKey('overlay-media')));
      expect(rect.top, 54);
      expect(rect.bottom, 852 - 34 - 64);
      update(() => infoHeight = 240);
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('overlay-media'))), rect);
      expect(events, ['mount']);
      update(() => clean = true);
      await tester.pump();
      expect(events, ['mount']);
      update(() => clean = false);
      await tester.pump();
      expect(events, ['mount']);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  GStorage.setting = _DefaultPreferencesBox();
  GStorage.localCache = _DefaultPreferencesBox();
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    // testWidgets supplies its own default, overriding the CLI timeout.
    binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));
  }
  test('shorts directly opens one player and resumes the last video', () async {
    final first = StoryVideoItem(aid: 1, bvid: 'BV1xx411c7mD', cid: 101);
    final resumed = StoryVideoItem(aid: 2, bvid: 'BV1xx411c7mQ', cid: 102);
    final source = _ShortsProbe(first)..items.add(first);
    final gate = source.presentationGate = Completer<void>();
    var handoffs = 0;
    final pending = source.openFeed(
      isSelected: () => true,
      beforeOpen: () => handoffs++,
    );
    await source.openFeed(isSelected: () => true, beforeOpen: () => handoffs++);
    expect(source.presentations, 1);
    expect(handoffs, 1);
    gate.complete();
    await pending;
    source.presentationGate = null;
    source.remember(resumed, 12345);
    await source.openFeed(isSelected: () => true, beforeOpen: () => handoffs++);
    expect(source.presented, same(resumed));
    expect(source.presentations, 2);
    source.onClose();
  });
  test('leaving shorts during discovery never opens a late player', () async {
    final source = _ShortsProbe(
      StoryVideoItem(aid: 1, bvid: 'BV1xx411c7mD', cid: 101),
    );
    final gate = source.loadingGate = Completer<void>();
    var selected = true, handedOff = false;
    final pending = source.openFeed(
      isSelected: () => selected,
      beforeOpen: () => handedOff = true,
    );
    selected = false;
    gate.complete();
    await pending;
    expect(source.presentations, 0);
    expect(handedOff, isFalse);
    source.onClose();
  });
  test(
    'late old-video skip responses cannot append to the new video',
    () async {
      final source = _BlockProbe();
      final old = source.querySponsorBlock(bvid: 'old', cid: 1);
      final newer = source.querySponsorBlock(bvid: 'new', cid: 2);
      source.requests[2]!.complete(
        Success([
          SegmentItemModel(
            cid: '2',
            category: 'sponsor',
            segment: [1000, 2000],
            uuid: 'new',
            videoDuration: 30000,
          ),
        ]),
      );
      await newer;
      expect(source.segmentProgressList.length, 1);
      source.requests[1]!.complete(
        Success([
          SegmentItemModel(
            cid: '1',
            category: 'sponsor',
            segment: [5000, 10000],
            uuid: 'old',
            videoDuration: 30000,
          ),
        ]),
      );
      await old;
      expect(source.segmentProgressList.length, 1);
      source.onClose();
    },
  );
  test('out-of-range skip segments never issue a seek to the ending', () async {
    final source = _BlockProbe();
    await source.handleSBData([
      SegmentItemModel(
        category: 'sponsor',
        segment: [1000, 45000],
        uuid: 'invalid',
        videoDuration: 45000,
      ),
    ]);
    expect(source.segmentProgressList, isEmpty);
    expect(source.seeks, isEmpty);
    source.onClose();
  });
  test('comments resume only playback paused by the panel', () {
    final policy = PanelPlaybackPolicy();
    expect(
      policy.update(obscured: false, playing: true),
      PanelPlaybackAction.none,
    );
    expect(
      policy.update(obscured: true, playing: true),
      PanelPlaybackAction.pause,
    );
    expect(
      policy.update(obscured: true, playing: false),
      PanelPlaybackAction.none,
    );
    expect(
      policy.update(obscured: false, playing: false),
      PanelPlaybackAction.resume,
    );
    expect(
      policy.update(obscured: true, playing: false),
      PanelPlaybackAction.none,
    );
    expect(
      policy.update(obscured: false, playing: false),
      PanelPlaybackAction.none,
    );
  });

  testWidgets(
    'inactive progress cannot become a full-page release error surface',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final originalBuilder = ErrorWidget.builder;
      final originalColor = RenderErrorBox.backgroundColor;
      addTearDown(() {
        ErrorWidget.builder = originalBuilder;
        RenderErrorBox.backgroundColor = originalColor;
      });
      // Reproduce the release-mode surface seen in the recording, while still
      // running with assertions so the underlying GetX exception is visible.
      RenderErrorBox.backgroundColor = const Color(0xF0C0C0C0);
      ErrorWidget.builder = (_) => ErrorWidget('');
      final boundary = GlobalKey();
      Widget page(Widget progress) => MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 24,
                  child: progress,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        page(Obx(() => const SizedBox(height: 48))),
      );
      expect(tester.takeException().toString(), contains('improper use'));
      // A bottom-positioned child has unbounded height. RenderErrorBox takes
      // its 100000px fallback, then page clipping makes it cover the screen.
      expect(tester.getSize(find.byType(ErrorWidget)), const Size(336, 100000));
      expect(
        tester.getTopLeft(find.byType(ErrorWidget)),
        const Offset(12, -99264),
      );
      Future<List<int>> pixel() async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (300 * image.width + 180) * 4;
        final result = List<int>.generate(4, (i) => bytes.getUint8(offset + i));
        image.dispose();
        return result;
      }

      await tester.runAsync(() async {
        final gray = await pixel();
        expect(gray.take(3), everyElement(inInclusiveRange(179, 182)));
      });
      await tester.pumpWidget(
        page(
          FeedProgressRegion(
            active: false,
            builder: (_) => const SizedBox.shrink(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(
        tester.getSize(find.byType(FeedProgressRegion)),
        const Size(336, 48),
      );
      await tester.runAsync(() async {
        expect(await pixel(), [0, 0, 0, 255]);
      });
      // Flutter checks this global before addTearDown callbacks execute.
      ErrorWidget.builder = originalBuilder;
      RenderErrorBox.backgroundColor = originalColor;
    },
  );

  testWidgets(
    'real progress bars survive preview, loading, active and return-page builds',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = PageController();
      addTearDown(pages.dispose);
      final progress = 10.obs;
      final duration = 0.obs;
      final buffered = 0.obs;
      addTearDown(() async {
        // GetX observers must unsubscribe before their source streams close.
        await tester.pumpWidget(const SizedBox.shrink());
        progress.close();
        duration.close();
        buffered.close();
      });
      var playing = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return FeedPager(
                controller: pages,
                itemCount: 3,
                onSettled: (_) {},
                itemBuilder: (context, index) {
                  final active = playing == index;
                  return FeedPage(
                    content: const ColoredBox(color: Colors.black),
                    controls: Stack(
                      children: [
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 24,
                          child: FeedProgressRegion(
                            active: active,
                            builder: (_) => ProgressBar(
                              key: ValueKey('progress-$index'),
                              progress: active ? progress.value : 0,
                              total: active ? duration.value : 100,
                              buffered: active ? buffered.value : 0,
                              progressBarColor: Colors.pink,
                              baseBarColor: Colors.white24,
                              bufferedBarColor: Colors.pinkAccent,
                              thumbColor: Colors.pink,
                              thumbGlowColor: Colors.pinkAccent,
                              barHeight: 3.5,
                              thumbRadius: 7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Bring the adjacent preview onscreen before activating its playback.
      final drag = await tester.startGesture(const Offset(180, 500));
      await drag.moveBy(const Offset(0, -380));
      await tester.pump();
      expect(find.byKey(const ValueKey('progress-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      await drag.up();
      await tester.pumpAndSettle();
      // While the next video loads, both pages display saved progress.
      update(() => playing = -1);
      await tester.pump();
      expect(tester.takeException(), isNull);
      update(() => playing = 1);
      duration.value = 120;
      buffered.value = 30;
      await tester.pump();
      progress.value = 23;
      await tester.pump();
      final bar = tester.widget<ProgressBar>(
        find.byKey(const ValueKey('progress-1')),
      );
      expect(bar.progress, 23);
      expect(bar.total, 120);
      expect(bar.buffered, 30);
      expect(tester.takeException(), isNull);
      update(() => playing = 0);
      pages.jumpToPage(0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    },
  );

  testWidgets(
    'original progress bar activates, seeks in milliseconds and cancels cleanly',
    (tester) async {
      var enabled = false;
      var dragging = false;
      int? seek;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: SizedBox(
                  width: 320,
                  height: 48,
                  child: ProgressBar(
                    storyThumb: true,
                    progress: 20,
                    buffered: 60,
                    total: 100,
                    progressBarColor: Colors.white,
                    baseBarColor: Colors.white24,
                    bufferedBarColor: Colors.white54,
                    thumbColor: Colors.white,
                    thumbGlowColor: Colors.white24,
                    barHeight: 3.5,
                    thumbRadius: 7,
                    onDragStart: enabled
                        ? (_) {
                            dragging = true;
                          }
                        : null,
                    onDragEnd: enabled
                        ? () {
                            dragging = false;
                          }
                        : null,
                    onSeek: enabled
                        ? (value) {
                            seek = value;
                          }
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      );
      update(() => enabled = true);
      await tester.pump();
      final rect = tester.getRect(find.byType(ProgressBar));
      final drag = await tester.startGesture(
        Offset(rect.left + 40, rect.center.dy),
      );
      await drag.moveBy(const Offset(200, 0));
      await drag.up();
      await tester.pump();
      expect(seek, inInclusiveRange(70000, 85000));
      expect(dragging, isFalse);
      seek = null;
      final cancelled = await tester.startGesture(
        Offset(rect.left + 80, rect.center.dy),
      );
      await cancelled.moveBy(const Offset(30, 0));
      await cancelled.cancel();
      await tester.pump();
      expect(dragging, isFalse);
      expect(seek, isNull);
      update(() => enabled = false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test('default accent text has accessible contrast in every theme', () {
    for (final brightness in Brightness.values) {
      final scheme = AppDesign.scheme(
        ColorScheme.fromSeed(seedColor: Colors.pink, brightness: brightness),
        defaultAccent: true,
      );
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
      }

      expect(
        contrast(scheme.primary, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surfaceContainerLowest),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets(
    'video and controls move together; cancelled turns keep the current item',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = PageController();
      addTearDown(pages.dispose);
      final settled = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedPager(
              controller: pages,
              itemCount: 3,
              onSettled: settled.add,
              itemBuilder: (context, index) => FeedPage(
                content: ColoredBox(
                  key: ValueKey('video-$index'),
                  color: Colors.black,
                ),
                controls: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      bottom: 70,
                      child: Text(
                        'Author $index',
                        key: ValueKey('author-$index'),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 150,
                      child: SizedBox(
                        key: ValueKey('actions-$index'),
                        width: 48,
                        height: 200,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Offset position(String key) =>
          tester.getTopLeft(find.byKey(ValueKey(key)));
      final video = position('video-0');
      final author = position('author-0');
      final actions = position('actions-0');
      final drag = await tester.startGesture(const Offset(180, 650));
      await drag.moveBy(const Offset(0, -440));
      await tester.pump();
      final delta = position('video-0') - video;
      expect(delta.dy, lessThan(-380));
      expect(position('author-0') - author, delta);
      expect(position('actions-0') - actions, delta);
      expect(settled, isEmpty);
      expect(
        position('author-1').dy - position('video-1').dy,
        closeTo(author.dy - video.dy, .1),
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(settled, [1]);
      expect(pages.page, closeTo(1, .001));
      settled.clear();
      final back = await tester.startGesture(const Offset(180, 100));
      await back.moveBy(const Offset(0, 440));
      await tester.pump(const Duration(milliseconds: 50));
      expect(settled, isEmpty);
      await back.moveBy(const Offset(0, -390));
      await tester.pump(const Duration(milliseconds: 250));
      await back.up();
      await tester.pumpAndSettle();
      expect(settled, [1]);
      expect(pages.page, closeTo(1, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'new media keeps its preview until a composed frame, without remounting video',
    (tester) async {
      final mounts = <String>[];
      Widget surface(bool ready, bool pending) => MaterialApp(
        home: FeedVideoSurface(
          video: _LifetimeProbe(events: mounts),
          preview: const ColoredBox(
            key: ValueKey('preview'),
            color: Colors.red,
          ),
          ready: ready,
          pending: pending,
        ),
      );
      await tester.pumpWidget(surface(false, true));
      expect(mounts, ['mount']);
      expect(find.byKey(const ValueKey('preview')), findsOneWidget);
      expect(find.text('加载中...'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(surface(true, false));
      // A ready event may only uncover the preview on the following composition.
      expect(find.byKey(const ValueKey('preview')), findsOneWidget);
      await tester.pump();
      expect(find.byKey(const ValueKey('preview')), findsNothing);
      expect(find.text('加载中...'), findsNothing);
      expect(mounts, ['mount']);
      await tester.pumpWidget(surface(false, true));
      expect(find.byKey(const ValueKey('preview')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 699));
      expect(find.text('加载中...'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('加载中...'), findsOneWidget);
      await tester.pumpWidget(surface(true, false));
      await tester.pump();
      expect(find.text('加载中...'), findsNothing);
      expect(mounts, ['mount']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(mounts, ['mount', 'dispose']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late ready callbacks cannot expose a replaced media and buffering keeps the last frame',
    (tester) async {
      Widget surface(bool ready, bool pending) => MaterialApp(
        home: FeedVideoSurface(
          video: const ColoredBox(color: Colors.blue),
          preview: const ColoredBox(
            key: ValueKey('preview'),
            color: Colors.red,
          ),
          ready: ready,
          pending: pending,
        ),
      );
      await tester.pumpWidget(surface(true, false));
      await tester.pumpWidget(surface(false, true));
      await tester.pump();
      expect(find.byKey(const ValueKey('preview')), findsOneWidget);
      await tester.pumpWidget(surface(true, false));
      await tester.pump();
      await tester.pumpWidget(surface(true, true));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('preview')), findsNothing);
      expect(find.text('加载中...'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'home portrait tags use video geometry, rotation and explicit API hints',
    () {
      Map<String, dynamic> card({
        Map? dimension,
        String? reason,
        String? uri,
      }) => {
        'param': '1',
        'bvid': 'BV1xx411c7mD',
        'card_goto': 'av',
        'title': 'test',
        'player_args': {'aid': 1, 'cid': 2, 'duration': 60},
        'dimension': dimension,
        'rcmd_reason': reason,
        'uri': uri,
      };
      expect(
        RcmdVideoItemAppModel.fromJson(
          card(dimension: {'width': 1080, 'height': 1920}),
        ).isPortraitVideo,
        isTrue,
      );
      expect(
        RcmdVideoItemAppModel.fromJson(
          card(dimension: {'width': 1920, 'height': 1080}, reason: '竖屏'),
        ).isPortraitVideo,
        isFalse,
      );
      expect(
        RcmdVideoItemAppModel.fromJson(
          card(dimension: {'width': 1920, 'height': 1080, 'rotate': 1}),
        ).isPortraitVideo,
        isTrue,
      );
      final hinted = RcmdVideoItemAppModel.fromJson(card(reason: '竖屏'));
      expect(hinted.rcmdReason, '竖屏');
      expect(hinted.isPortraitVideo, isTrue);
      expect(
        RcmdVideoItemAppModel.fromJson(
          card(uri: 'bilibili://video/1?player_width=1080&player_height=1920'),
        ).isPortraitVideo,
        isTrue,
      );
      expect(RcmdVideoItemAppModel.fromJson(card()).isPortraitVideo, isFalse);
      final horizontal = StoryVideoItem.tryParse({
        'card_goto': 'vertical_av',
        'param': '1',
        'stat': {'reply': 52, 'coin': 11, 'favorite': 168, 'share': 3},
        'dimension': {'width': 1920, 'height': 1080},
      })!;
      expect(horizontal.isPortraitVideo, isFalse);
      expect(horizontal.storyStat?.reply, 52);
      expect(horizontal.storyStat?.coin, 11);
      expect(horizontal.storyStat?.favorite, 168);
      expect(horizontal.storyStat?.share, 3);
      expect(VideoPresentation.labels({'is_upower_exclusive': true}), ['充电专属']);
      expect(
        VideoPresentation.labels({
          'badges': [
            {'text': '专属内容'},
            {'text': '充电专属'},
          ],
        }),
        ['专属内容', '充电专属'],
      );
      expect(
        VideoPresentation.labels({'title': '充电的视频', 'badge': '普通内容'}),
        isEmpty,
      );
    },
  );

  testWidgets(
    'story video fits above variable metadata and retains the same element in clean mode',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <String>[];
      var height = 100.0;
      var clean = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return FeedStoryLayout(
                topInset: 100,
                bottomInset: 34,
                clean: clean,
                video: SizedBox(
                  key: const ValueKey('media'),
                  child: _LifetimeProbe(events: events),
                ),
                information: SizedBox(
                  height: height,
                  child: const ColoredBox(color: Colors.red),
                ),
                actions: const SizedBox(width: 56, height: 320),
                footer: const SizedBox(),
              );
            },
          ),
        ),
      );
      final center = tester.getCenter(find.byKey(const ValueKey('media'))).dy;
      expect(center, lessThan(852 / 2));
      update(() => height = 170);
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('media'))).dy,
        closeTo(center - 35, .1),
      );
      update(() => clean = true);
      await tester.pump();
      expect(events, ['mount']);
      update(() => clean = false);
      await tester.pump();
      expect(events, ['mount']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(events, ['mount', 'dispose']);
    },
  );

  testWidgets(
    'fixed navigation stays while video, tags, actions and footer slide as one story',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = PageController();
      addTearDown(pages.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              FeedPager(
                controller: pages,
                itemCount: 2,
                onSettled: (_) {},
                itemBuilder: (context, i) => FeedStoryLayout(
                  topInset: 100,
                  bottomInset: 34,
                  video: ColoredBox(
                    key: ValueKey('media-$i'),
                    color: Colors.blue,
                  ),
                  information: SizedBox(
                    key: ValueKey('info-$i'),
                    height: 130,
                    child: const FeedContentTags(labels: ['充电专属']),
                  ),
                  actions: SizedBox(
                    key: ValueKey('actions-$i'),
                    width: 56,
                    height: 320,
                  ),
                  footer: ColoredBox(
                    key: ValueKey('footer-$i'),
                    color: Colors.red,
                  ),
                ),
              ),
              const Positioned(
                top: 60,
                left: 0,
                child: SizedBox(
                  key: ValueKey('fixed-nav'),
                  width: 393,
                  height: 40,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      Offset point(String key) => tester.getTopLeft(find.byKey(ValueKey(key)));
      final initial = {
        for (final key in [
          'media-0',
          'info-0',
          'actions-0',
          'footer-0',
          'fixed-nav',
        ])
          key: point(key),
      };
      final drag = await tester.startGesture(const Offset(120, 340));
      await drag.moveBy(const Offset(0, -250));
      await tester.pump();
      final delta = point('media-0') - initial['media-0']!;
      expect(delta.dy, lessThan(-200));
      for (final key in ['info-0', 'actions-0', 'footer-0']) {
        expect(point(key) - initial[key]!, delta);
      }
      expect(point('fixed-nav'), initial['fixed-nav']);
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'story metadata and paid-content tags fit small phones, large text and desktop sizes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      for (final size in [
        const Size(320, 568),
        const Size(393, 852),
        const Size(468, 800),
        const Size(904, 480),
      ]) {
        tester.view.physicalSize = size;
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: FeedStoryLayout(
                  topInset: 90,
                  bottomInset: 24,
                  video: const ColoredBox(color: Colors.blue),
                  information: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FeedContentTags(labels: ['充电专属', '专属内容']),
                        const Text('UP主名字和视频标题较长时也应该完整适配', maxLines: 2),
                        const FeedFollowButton(followed: false),
                      ],
                    ),
                  ),
                  actions: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => const FeedActionButton(
                        icon: Icons.star,
                        label: '49.9万',
                        semantics: '互动',
                      ),
                    ),
                  ),
                  footer: const SizedBox(),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$size, scale=$scale');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('feed video stays opaque during page transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FeedPlayerReveal(child: ColoredBox(color: Colors.blue)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.descendant(
        of: find.byType(FeedPlayerReveal),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(FeedPlayerReveal),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(FeedPlayerReveal),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      Colors.black,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing, loading and failed feed covers cannot flash a light surface',
    (tester) async {
      final boundary = GlobalKey();
      for (final brightness in Brightness.values) {
        for (final state in ['missing', 'loading', 'failed']) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 120,
                    height: 200,
                    child: ColoredBox(
                      color: Colors.white,
                      child: state == 'missing'
                          ? const FeedCover(src: null)
                          : Builder(
                              builder: (context) {
                                // Exercise the real image callbacks without starting network IO.
                                final cover = const FeedCover(
                                  src: 'https://example.invalid/cover.jpg',
                                ).build(context) as ColoredBox;
                                final layout = cover.child as LayoutBuilder;
                                final layer = layout.builder(
                                  context,
                                  const BoxConstraints.tightFor(
                                    width: 120,
                                    height: 200,
                                  ),
                                ) as NetworkImgLayer;
                                final image =
                                    (layer.build(context) as ClipRRect).child
                                        as CachedNetworkImage;
                                expect(image.fadeInDuration, Duration.zero);
                                expect(image.fadeOutDuration, Duration.zero);
                                return state == 'loading'
                                    ? image.placeholder!(
                                        context,
                                        image.imageUrl,
                                      )
                                    : image.errorBuilder!(
                                        context,
                                        StateError('cover unavailable'),
                                        StackTrace.current,
                                      );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final surface = find.byType(ColoredBox).last;
          expect(tester.getSize(surface), const Size(120, 200));
          expect(
            surface,
            paints..rect(
              rect: const Rect.fromLTWH(0, 0, 120, 200),
              color: Colors.black,
            ),
            reason: '$brightness / $state',
          );
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'feed danmaku clears navigation even with hidden status bars and notches',
    (tester) async {
      for (final safeTop in [0.0, 24.0, 59.0]) {
        late double navigationTop;
        late double danmakuTop;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.only(top: safeTop),
              ),
              child: Builder(
                builder: (context) {
                  navigationTop = FeedChrome.navigationTop(context);
                  danmakuTop = FeedChrome.danmakuTop(context);
                  expect(FeedChrome.danmakuTop(context, mini: true), 44);
                  return Stack(
                    children: [
                      Positioned(
                        top: navigationTop,
                        left: 8,
                        width: 48,
                        height: FeedChrome.buttonExtent,
                        child: const SizedBox(key: ValueKey('feed-navigation')),
                      ),
                      Positioned.fill(
                        top: danmakuTop,
                        child: const ClipRect(
                          child: ColoredBox(
                            key: ValueKey('feed-danmaku'),
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        expect(navigationTop, greaterThanOrEqualTo(safeTop));
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('feed-danmaku'))).dy,
          greaterThan(
            tester
                .getBottomLeft(find.byKey(const ValueKey('feed-navigation')))
                .dy,
          ),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'follow pill handles pending requests, relation states and large text',
    (tester) async {
      final request = Completer<void>();
      var calls = 0;
      Widget button({
        bool followed = false,
        int? attribute,
        double scale = 1,
      }) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: FeedFollowButton(
              followed: followed,
              attribute: attribute,
              onPressed: () {
                calls++;
                return request.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(button());
      expect(
        tester.getSize(find.byType(FeedFollowButton)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byType(FeedFollowButton));
      await tester.pump();
      await tester.tap(find.byType(FeedFollowButton));
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      request.complete();
      await tester.pumpAndSettle();
      for (final relation in [(2, '已关注'), (6, '互相关注'), (-10, '特别关注')]) {
        await tester.pumpWidget(
          button(followed: true, attribute: relation.$1, scale: 2.5),
        );
        expect(find.text(relation.$2), findsOneWidget);
        expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byType(FeedFollowButton));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 3);
    },
  );

  testWidgets(
    'desktop keys work without swallowing text or Command shortcuts',
    (tester) async {
      final commands = <FeedCommand>[];
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedDesktopInput(
              onCommand: commands.add,
              child: TextField(focusNode: field),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      expect(commands, [FeedCommand.next, FeedCommand.pip]);
      commands.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(commands, isEmpty);
      field.requestFocus();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'comment');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      expect(commands, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(field.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(commands, [FeedCommand.playPause]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wheel inertia turns one page and comments scroll independently',
    (tester) async {
      final pages = PageController();
      final gate = FeedWheelGate();
      final comments = ScrollController();
      addTearDown(pages.dispose);
      addTearDown(gate.dispose);
      addTearDown(comments.dispose);
      var turns = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: FeedWheelRegion(
                    gate: gate,
                    onTurn: (direction) {
                      turns++;
                      pages.animateToPage(
                        (pages.page ?? 0).round() + direction,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      );
                    },
                    child: FeedPager(
                      controller: pages,
                      desktop: true,
                      itemCount: 4,
                      onSettled: (_) {},
                      itemBuilder: (_, index) => ColoredBox(
                        color: Colors.black,
                        child: Center(child: Text('Video $index')),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: ListView.builder(
                    controller: comments,
                    itemCount: 50,
                    itemExtent: 60,
                    itemBuilder: (_, index) => Text('Comment $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(100, 200),
            scrollDelta: const Offset(0, 80),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(turns, 1);
      expect(pages.page, closeTo(1, .001));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(750, 200),
          scrollDelta: const Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(comments.offset, greaterThan(0));
      expect(turns, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'desktop trackpad follows the page and settles on the next video',
    (tester) async {
      final pages = PageController();
      addTearDown(pages.dispose);
      final settled = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FeedPager(
            controller: pages,
            desktop: true,
            itemCount: 3,
            onSettled: settled.add,
            itemBuilder: (_, index) =>
                ColoredBox(color: Colors.black, child: Text('Video $index')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(const Offset(200, 500));
      await gesture.panZoomUpdate(
        const Offset(200, 500),
        pan: const Offset(0, -420),
      );
      await tester.pump();
      expect(pages.page, greaterThan(.5));
      expect(settled, isEmpty);
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(settled, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('small window resize retains the current page and one player', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _PlayerProbe.mounts = 0;
    _PlayerProbe.disposals = 0;
    final pages = PageController(initialPage: 1);
    addTearDown(pages.dispose);
    var small = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return FeedDesktopFrame(
              enabled: !small,
              child: FeedPager(
                controller: pages,
                itemCount: 3,
                onSettled: (_) {},
                itemBuilder: (_, index) => index == 1
                    ? const _PlayerProbe(key: ValueKey('current-player'))
                    : const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('current-player'))).width,
      1100,
    );
    for (final size in [
      const Size(280, 498),
      const Size(500, 280),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      update(() => small = size.width < 1100);
      await tester.pumpAndSettle();
      expect(pages.page, closeTo(1, .001));
      expect(_PlayerProbe.mounts, 1);
      expect(_PlayerProbe.disposals, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(_PlayerProbe.disposals, 1);
  });

  testWidgets('detail actions have room for large text at 360dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 760),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                height: ActionItem.heightFor(context),
                child: const Row(
                  children: [
                    ActionItem(
                      icon: Icon(Icons.thumb_up_outlined),
                      semanticsLabel: 'Like',
                      text: '12.3万',
                    ),
                    ActionItem(
                      icon: Icon(Icons.thumb_down_outlined),
                      semanticsLabel: 'Dislike',
                      text: '点踩',
                    ),
                    ActionItem(
                      icon: Icon(Icons.toll_outlined),
                      semanticsLabel: 'Coin',
                      text: '3210',
                    ),
                    ActionItem(
                      icon: Icon(Icons.star_border),
                      semanticsLabel: 'Favorite',
                      text: '4.5万',
                    ),
                    ActionItem(
                      icon: Icon(Icons.watch_later_outlined),
                      semanticsLabel: 'Later',
                      text: '再看',
                    ),
                    ActionItem(
                      icon: Icon(Icons.reply),
                      semanticsLabel: 'Share',
                      text: '1820',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Row)).height, greaterThanOrEqualTo(64));
  });

  for (final size in [
    const Size(360, 760),
    const Size(430, 932),
    const Size(840, 600),
  ]) {
    testWidgets(
      'comment docking preserves one player at ${size.width} × ${size.height}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        _PlayerProbe.mounts = 0;
        _PlayerProbe.disposals = 0;
        final pages = PageController(initialPage: 1);
        addTearDown(pages.dispose);
        var open = false;
        var expanded = false;
        late StateSetter update;
        final screenshotKey = GlobalKey();
        final source = ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.dark,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: AppDesign.scheme(source, defaultAccent: true),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: Scaffold(
                backgroundColor: Colors.black,
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return RepaintBoundary(
                      key: screenshotKey,
                      child: FeedViewport(
                        video: PageView(
                          controller: pages,
                          scrollDirection: Axis.vertical,
                          physics: const NeverScrollableScrollPhysics(),
                          children: const [
                            SizedBox.expand(),
                            _PlayerProbe(key: ValueKey('player')),
                            SizedBox.expand(),
                          ],
                        ),
                        controls: const Stack(
                          key: ValueKey('controls'),
                          children: [
                            Positioned(
                              right: 8,
                              bottom: 60,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FeedActionButton(
                                    icon: Icons.thumb_up,
                                    label: '12.3万',
                                    semantics: '点赞',
                                    color: AppDesign.like,
                                  ),
                                  FeedActionButton(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    label: '2310',
                                    semantics: '评论',
                                  ),
                                  FeedActionButton(
                                    icon: Icons.star_rounded,
                                    label: '4.5万',
                                    semantics: '收藏',
                                    color: AppDesign.favorite,
                                  ),
                                  FeedActionButton(
                                    icon: Icons.reply_rounded,
                                    label: '分享',
                                    semantics: '分享',
                                  ),
                                  FeedActionButton(
                                    icon: Icons.more_vert_rounded,
                                    label: '更多',
                                    semantics: '更多',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        expanded: expanded,
                        sheetHeader: const SizedBox(
                          height: 60,
                          key: ValueKey('header'),
                          child: Center(child: Text('Comments')),
                        ),
                        comments: open
                            ? const ColoredBox(
                                color: AppDesign.playerSheet,
                                child: Center(
                                  child: Text(
                                    'Comment list',
                                    key: ValueKey('comments'),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_PlayerProbe.mounts, 1);
        expect(find.byKey(const ValueKey('controls')), findsOneWidget);
        update(() => open = true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_PlayerProbe.mounts, 1);
        expect(_PlayerProbe.disposals, 0);
        expect(pages.page, closeTo(1, .001));
        expect(find.byKey(const ValueKey('controls')), findsNothing);
        final player = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('player')),
        );
        final playerEnd = player.localToGlobal(
          player.size.bottomRight(Offset.zero),
        );
        final header = tester.getRect(find.byKey(const ValueKey('header')));
        if (size.width < 600) {
          expect(playerEnd.dy, lessThanOrEqualTo(header.top + .1));
          expect(header.top, closeTo(size.height * .38, .1));
          expect(player.size, Size(size.width, size.height * .38));
        } else {
          expect(playerEnd.dx, lessThanOrEqualTo(header.left + .1));
          expect(header.width, closeTo(380, .1));
          expect(player.size, Size(size.width - 380, size.height));
        }
        await tester.runAsync(() async {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/ui-previews')
            ..createSync(recursive: true);
          File('${directory.path}/comments-${size.width.toInt()}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        update(() => expanded = true);
        await tester.pumpAndSettle();
        expect(_PlayerProbe.mounts, 1);
        expect(tester.takeException(), isNull);
        if (size.width < 600) {
          expect(
            tester.getRect(find.byKey(const ValueKey('header'))).top,
            closeTo(size.height * .08, .1),
          );
        }
        update(() => open = false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('controls')), findsOneWidget);
        expect(_PlayerProbe.mounts, 1);
        expect(_PlayerProbe.disposals, 0);
        expect(pages.page, closeTo(1, .001));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(_PlayerProbe.disposals, 1);
      },
    );
  }
}

class _PlayerProbe extends StatefulWidget {
  const _PlayerProbe({super.key});
  static int mounts = 0;
  static int disposals = 0;
  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  void initState() {
    super.initState();
    _PlayerProbe.mounts++;
  }

  @override
  void dispose() {
    _PlayerProbe.disposals++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF433868), Color(0xFF943959)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    child: Center(
      child: Icon(Icons.movie_outlined, size: 80, color: Colors.white70),
    ),
  );
}

class _LifetimeProbe extends StatefulWidget {
  const _LifetimeProbe({required this.events});
  final List<String> events;
  @override
  State<_LifetimeProbe> createState() => _LifetimeProbeState();
}

class _LifetimeProbeState extends State<_LifetimeProbe> {
  @override
  void initState() {
    super.initState();
    widget.events.add('mount');
  }

  @override
  void dispose() {
    widget.events.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.blue);
}

class _ShortsProbe extends ShortsController {
  _ShortsProbe(this.seed);
  final StoryVideoItem seed;
  Completer<void>? loadingGate, presentationGate;
  int presentations = 0;
  StoryVideoItem? presented;
  @override
  Future<void> onRefresh() async {
    await loadingGate?.future;
    items.assignAll([seed]);
  }

  @override
  Future<void> presentFeed(StoryVideoItem item) async {
    presentations++;
    presented = item;
    await presentationGate?.future;
  }
}

class _BlockPreferences with BlockConfigMixin {
  @override
  final enableList = {'sponsor'};
}

class _BlockProbe extends GetxController with BlockMixin {
  final _config = _BlockPreferences();
  final requests = <int, Completer<LoadingState<List<SegmentItemModel>>>>{};
  final seeks = <Duration>[];
  @override
  BlockConfigMixin get blockConfig => _config;
  @override
  Player? get player => null;
  @override
  bool get autoPlay => false;
  @override
  int get timeLength => 30000;
  @override
  bool get preInitPlayer => false;
  @override
  int get currPosInMilliseconds => 0;
  @override
  bool get isUgc => true;
  @override
  Future<void> seekTo(Duration position, {required bool isSeek}) async {
    seeks.add(position);
  }

  @override
  Widget buildItem(Object item, Animation<double> animation) =>
      const SizedBox.shrink();
  @override
  Future<LoadingState<List<SegmentItemModel>>> requestBlockSegments({
    required String bvid,
    required int cid,
  }) {
    final pending = Completer<LoadingState<List<SegmentItemModel>>>();
    requests[cid] = pending;
    return pending.future;
  }
}

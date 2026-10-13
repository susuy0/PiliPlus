import 'package:PiliPlus/pages/video/vertical_feed/desktop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:PiliPlus/pages/video/vertical_feed/pager.dart';
import 'package:PiliPlus/pages/video/vertical_feed/cover.dart';
import 'package:PiliPlus/pages/video/vertical_feed/chrome.dart';
import 'package:PiliPlus/pages/video/vertical_feed/follow_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:hive_ce/hive.dart';

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

void main() {
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

  testWidgets('video reveal fades in and respects reduced motion', (
    tester,
  ) async {
    Widget page(bool reduced) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const FeedPlayerReveal(child: ColoredBox(color: Colors.blue)),
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(true));
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing, loading and failed feed covers cannot flash a light surface',
    (tester) async {
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('feed-cover-test');
        Hive.init(directory.path);
        GStorage.setting = await Hive.openBox('feed-cover-settings');
        GStorage.localCache = await Hive.openBox('feed-cover-cache');
      });
      addTearDown(
        () => tester.runAsync(() async {
          await GStorage.setting.close();
          await GStorage.localCache.close();
          await directory.delete(recursive: true);
        }),
      );
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
          await tester.pump();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            for (final offset in [0, (100 * 120 + 60) * 4, data.length - 4]) {
              expect(data.sublist(offset, offset + 4), [
                0,
                0,
                0,
                255,
              ], reason: '$brightness / $state');
            }
            image.dispose();
          });
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
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
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

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

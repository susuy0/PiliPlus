import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;

/// Commit playback only after both the finger and page snap have stopped.
class FeedPager extends StatelessWidget {
  const FeedPager({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.onSettled,
    this.onDragStart,
    this.enabled = true,
    this.desktop = false,
  });
  final PageController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onSettled;
  final VoidCallback? onDragStart;
  final bool enabled;
  final bool desktop;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification) onDragStart?.call();
          if (notification is ScrollEndNotification) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted ||
                  !controller.hasClients ||
                  controller.position.isScrollingNotifier.value)
                return;
              final index = controller.page?.round();
              if (index != null && index >= 0 && index < itemCount)
                onSettled(index);
            });
          }
          return false;
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            overscroll: false,
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              if (desktop) PointerDeviceKind.mouse,
            },
          ),
          child: PageView.builder(
            controller: controller,
            scrollDirection: Axis.vertical,
            allowImplicitScrolling: true,
            physics: enabled
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
      );
}

/// Every overlay shares the same clipped, moving page as its video.
class FeedPage extends StatelessWidget {
  const FeedPage({super.key, required this.content, this.controls});
  final Widget content;
  final Widget? controls;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.hardEdge,
    children: [content, ?controls],
  );
}

class FeedPlayerReveal extends StatelessWidget {
  const FeedPlayerReveal({super.key, required this.child});
  final Widget child;
  @override
  // Native video textures must stay opaque. The enclosing pager supplies the
  // transition; fading the whole texture forces an offscreen blend on iOS.
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: child,
  );
}

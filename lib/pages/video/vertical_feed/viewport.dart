import 'dart:math' as math;

import 'package:PiliPlus/common/design_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps the full-size player mounted while docking comments. Only its paint
/// transform changes, so opening a sheet never creates a second decoder.
class FeedViewport extends StatelessWidget {
  const FeedViewport({
    super.key,
    required this.video,
    required this.controls,
    this.comments,
    this.expanded = false,
    this.sheetHeader,
  });
  final Widget video;
  final Widget controls;
  final Widget? comments;
  final Widget? sheetHeader;
  final bool expanded;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 600 || box.maxWidth > box.maxHeight;
      final open = comments != null;
      final sheetWidth = math.min(380.0, box.maxWidth * .48);
      final availableWidth = open && wide
          ? box.maxWidth - sheetWidth
          : box.maxWidth;
      final availableHeight = open && !wide
          ? box.maxHeight * (expanded ? .08 : .38)
          : box.maxHeight;
      final scale = math.min(
        availableWidth / box.maxWidth,
        availableHeight / box.maxHeight,
      );
      final target = Rect.fromLTWH(
        (availableWidth - box.maxWidth * scale) / 2,
        (availableHeight - box.maxHeight * scale) / 2,
        scale,
        scale,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: TweenAnimationBuilder<Rect?>(
              tween: RectTween(end: target),
              duration: AppDesign.motion(context, 320),
              curve: Curves.easeOutCubic,
              child: video,
              builder: (context, rect, child) => Transform.translate(
                offset: rect!.topLeft,
                child: Transform.scale(
                  scale: rect.width,
                  alignment: Alignment.topLeft,
                  child: child,
                ),
              ),
            ),
          ),
          if (!open) controls,
          if (open) ...[
            Positioned(
              left: 0,
              top: 0,
              width: availableWidth,
              height: availableHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              left: wide ? null : 0,
              top: wide ? 0 : availableHeight,
              width: wide ? sheetWidth : null,
              child: ClipRRect(
                borderRadius: wide ? BorderRadius.zero : AppDesign.sheetRadius,
                child: Material(
                  color: AppDesign.playerSheet,
                  child: Column(
                    children: [
                      ?sheetHeader,
                      Expanded(child: comments!),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

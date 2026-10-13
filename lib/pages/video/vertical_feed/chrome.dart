import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Share geometry between the moving navigation row and the danmaku canvas.
abstract final class FeedChrome {
  static const buttonExtent = 48.0;
  static double safeTop(BuildContext context) => math.max(
    MediaQuery.paddingOf(context).top,
    MediaQuery.viewPaddingOf(context).top,
  );
  static double navigationTop(BuildContext context) => safeTop(context) + 8;
  static double danmakuTop(BuildContext context, {bool mini = false}) =>
      mini ? 44 : navigationTop(context) + buttonExtent + 8;
}

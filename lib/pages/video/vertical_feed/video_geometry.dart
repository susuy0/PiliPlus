import 'dart:math' as math;

typedef FeedVideoBounds = ({
  double left,
  double top,
  double width,
  double height,
});

/// Match the contain fit used by the original player, including its black bars.
FeedVideoBounds feedVideoBounds(
  double width,
  double height, {
  required double mediaWidth,
  required double mediaHeight,
}) {
  if (width <= 0 ||
      height <= 0 ||
      mediaWidth <= 0 ||
      mediaHeight <= 0 ||
      !mediaWidth.isFinite ||
      !mediaHeight.isFinite) {
    return (
      left: 0,
      top: 0,
      width: math.max(0, width),
      height: math.max(0, height),
    );
  }
  final scale = math.min(width / mediaWidth, height / mediaHeight);
  final w = mediaWidth * scale, h = mediaHeight * scale;
  return (left: (width - w) / 2, top: (height - h) / 2, width: w, height: h);
}

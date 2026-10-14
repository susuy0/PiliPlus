/// A reused VideoController's first-frame future completes only once. Validate
/// the newly opened media, decoded frame and texture on every feed switch.
abstract final class FeedFrameReadiness {
  static bool ready({
    required String expectedPath,
    required String path,
    required int width,
    required int height,
    required double textureWidth,
    required double textureHeight,
    required bool buffering,
    required String pictureType,
    required int positionMs,
    required int startMs,
  }) =>
      expectedPath.isNotEmpty &&
      path == expectedPath &&
      width > 0 &&
      height > 0 &&
      textureWidth > 1 &&
      textureHeight > 1 &&
      !buffering &&
      (const {'I', 'P', 'B'}.contains(pictureType) ||
          positionMs > startMs + 100);
}

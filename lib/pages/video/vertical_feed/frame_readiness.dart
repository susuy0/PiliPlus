/// A reused VideoController's first-frame future completes only once. Validate
/// the newly opened media, decoded frame and texture on every feed switch.
abstract final class FeedFrameReadiness {
  /// Missing native support falls back to decoded-media checks. A registered
  /// but unchanged texture is not a new picture, even if the clock advances.
  static bool freshTexture({required int? serial, required int? before}) =>
      serial == null || serial > (before ?? 0);

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

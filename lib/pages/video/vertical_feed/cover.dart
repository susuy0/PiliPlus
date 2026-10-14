import 'package:PiliPlus/common/design_tokens.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

/// The preview is exposed while switching playback.
/// Keep loading, missing and failed covers opaque, independent of app theme.
class FeedCover extends StatelessWidget {
  const FeedCover({super.key, required this.src});
  final String? src;

  static Future<void> prefetch(BuildContext context, String? src) async {
    if (src?.isNotEmpty != true) return;
    final size = MediaQuery.sizeOf(context);
    final provider = ResizeImage.resizeIfNeeded(
      size.width <= size.height ? size.width.cacheSize(context) : null,
      size.width > size.height ? size.height.cacheSize(context) : null,
      CachedNetworkImageProvider(ImageUtils.thumbnailUrl(src, 1)),
    );
    await precacheImage(provider, context, onError: (_, _) {});
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppDesign.playerBackground,
    child: LayoutBuilder(
      builder: (context, box) => NetworkImgLayer(
        src: src,
        width: box.maxWidth,
        height: box.maxHeight,
        fit: BoxFit.contain,
        borderRadius: BorderRadius.zero,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        getPlaceHolder: () => const ColoredBox(
          color: AppDesign.playerBackground,
          child: SizedBox.expand(),
        ),
      ),
    ),
  );
}

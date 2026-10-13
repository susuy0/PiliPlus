import 'package:PiliPlus/common/design_tokens.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:material_ui/material_ui.dart';

/// The preview is exposed while switching playback and fading in the player.
/// Keep loading, missing and failed covers opaque, independent of app theme.
class FeedCover extends StatelessWidget {
  const FeedCover({super.key, required this.src});
  final String? src;

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

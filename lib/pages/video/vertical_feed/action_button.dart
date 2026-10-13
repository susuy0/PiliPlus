import 'package:PiliPlus/common/design_tokens.dart';
import 'package:material_ui/material_ui.dart';

class FeedActionButton extends StatelessWidget {
  const FeedActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semantics,
    this.onTap,
    this.color = Colors.white,
    this.onLongPress,
    this.onStartTriple,
    this.onCancelTriple,
    this.tripleAnimation,
  });
  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback? onTap;
  final Color color;
  final VoidCallback? onLongPress;
  final VoidCallback? onStartTriple;
  final void Function([bool])? onCancelTriple;
  final Animation<double>? tripleAnimation;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$semantics $label',
    child: InkWell(
      onTap: onStartTriple == null ? onTap : null,
      onLongPress: onLongPress,
      onTapDown: onStartTriple == null ? null : (_) => onStartTriple!(),
      onTapUp: onCancelTriple == null ? null : (_) => onCancelTriple!(true),
      onTapCancel: onCancelTriple == null ? null : () => onCancelTriple!(),
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        width: MediaQuery.textScalerOf(context).scale(12) > 15 ? 64 : 56,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (tripleAnimation != null)
                    AnimatedBuilder(
                      animation: tripleAnimation!,
                      builder: (context, _) => CircularProgressIndicator(
                        value: tripleAnimation!.value,
                        strokeWidth: 2,
                        color: AppDesign.playerPrimary,
                      ),
                    ),
                  Icon(
                    icon,
                    size: 30,
                    color: color,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.33,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

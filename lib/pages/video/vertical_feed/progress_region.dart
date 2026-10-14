import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Only the playing page reads live progress. Other pages use saved values.
class FeedProgressRegion extends StatelessWidget {
  const FeedProgressRegion({
    super.key,
    required this.active,
    required this.builder,
    this.height = 48,
  });

  final bool active;
  final double height;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    // An Obx without any Rx reads throws in release too. Keep the height
    // outside the observer so a failed build cannot occupy the whole page.
    child: active ? Obx(() => builder(context)) : builder(context),
  );
}

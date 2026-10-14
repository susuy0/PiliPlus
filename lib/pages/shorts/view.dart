import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/shorts/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// The tab hands off to the actual player; it no longer presents a cover grid.
class ShortsPage extends StatefulWidget {
  const ShortsPage({super.key});
  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage>
    with AutomaticKeepAliveClientMixin {
  final controller = Get.putOrFind(ShortsController.new);
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Obx(() {
          final error = controller.error.value;
          if (error == null) return const CircularProgressIndicator();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Get.find<HomeController>().openShorts(),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          );
        }),
      ),
    );
  }
}

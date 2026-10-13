import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/pages/shorts/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ShortsPage extends StatefulWidget {
  const ShortsPage({super.key});
  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage>
    with AutomaticKeepAliveClientMixin {
  final controller = Get.put(ShortsController());
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth < 600
            ? 2
            : box.maxWidth < 840
            ? 3
            : 4;
        final width = (box.maxWidth - 24 - (columns - 1) * 12) / columns;
        return refreshIndicator(
          onRefresh: controller.onRefresh,
          child: Obx(
            () => CustomScrollView(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: controller.items.isEmpty
                                ? null
                                : () => VideoCardV(
                                    videoItem: controller.items.first,
                                  ).onPushDetail(),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('连续观看'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '刷新短视频',
                          onPressed: controller.loading.value
                              ? null
                              : controller.onRefresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
                if (controller.items.isEmpty && controller.loading.value)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (controller.items.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverGrid.builder(
                      itemCount: controller.items.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent:
                            width * 4 / 3 +
                            MediaQuery.textScalerOf(context).scale(94),
                      ),
                      itemBuilder: (context, index) =>
                          VideoCardV(videoItem: controller.items[index]),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
                    child: Center(
                      child: controller.loading.value
                          ? const CircularProgressIndicator()
                          : TextButton.icon(
                              onPressed: controller.items.isEmpty
                                  ? controller.onRefresh
                                  : controller.loadMore,
                              icon: const Icon(Icons.refresh),
                              label: Text(controller.error.value ?? '加载更多短视频'),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

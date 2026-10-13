import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/video/story.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ShortsController extends GetxController with ScrollOrRefreshMixin {
  @override
  final scrollController = ScrollController();
  final items = <StoryVideoItem>[].obs;
  final loading = false.obs;
  final error = RxnString();
  int _page = 0;
  final _session = 'discovery-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(() {
      if (scrollController.position.extentAfter < 600) loadMore();
    });
    onRefresh();
  }

  @override
  Future<void> onRefresh() => _load(refresh: true);
  Future<void> loadMore() => _load(refresh: false);

  Future<void> _load({required bool refresh}) async {
    if (loading.value || isClosed) return;
    loading.value = true;
    error.value = null;
    final page = refresh ? 1 : _page + 1;
    try {
      // Story's discovery page accepts an empty seed; subsequent playback is
      // seeded with the exact video the user selects from this list.
      final result = await VideoHttp.storyFeed(
        aid: 0,
        bvid: '',
        cid: 0,
        page: page,
        sessionId: _session,
      );
      if (isClosed) return;
      if (result case Success(:final response)) {
        final ids = refresh ? <int?>{} : items.map((i) => i.aid).toSet();
        final unique = response.where((i) => ids.add(i.aid)).toList();
        if (refresh) {
          items.assignAll(unique);
        } else {
          items.addAll(unique);
        }
        _page = page;
        if (items.isEmpty) error.value = '暂时没有短视频，稍后再试';
      } else {
        error.value = '短视频加载失败，请重试';
      }
    } catch (_) {
      if (!isClosed) error.value = '网络连接失败，请重试';
    } finally {
      if (!isClosed) loading.value = false;
    }
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}

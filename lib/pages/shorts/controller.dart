import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/utils/page_utils.dart';
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
  Future<void>? _loadTask;
  bool _opening = false;
  StoryVideoItem? _resume;
  int _resumePosition = 0;

  void remember(StoryVideoItem item, int positionMs) {
    _resume = item;
    _resumePosition = positionMs;
  }

  Future<void> openFeed({
    required bool Function() isSelected,
    required void Function() beforeOpen,
  }) async {
    if (_opening || isClosed) return;
    _opening = true;
    error.value = null;
    try {
      if (_resume == null && items.isEmpty) await onRefresh();
      if (isClosed || !isSelected()) return;
      final item = _resume ?? (items.isEmpty ? null : items.first);
      if (item == null) return;
      if (item.cid == null || item.cid == 0) {
        final resolved = await SearchHttp.ab2cWithDimension(
          aid: item.aid,
          bvid: item.bvid,
        );
        if (isClosed || !isSelected()) return;
        item.cid = resolved?.cid;
        item.dimension ??= resolved?.dimension;
      }
      if (item.cid == null || item.cid == 0) {
        error.value = '视频暂时无法播放，请重试';
        return;
      }
      beforeOpen();
      await presentFeed(item);
    } catch (_) {
      if (!isClosed) error.value = '短视频加载失败，请重试';
    } finally {
      _opening = false;
    }
  }

  Future<void> presentFeed(StoryVideoItem item) async {
    await PageUtils.toVideoPage(
      aid: item.aid,
      bvid: item.bvid,
      cid: item.cid!,
      title: item.title,
      cover: item.cover,
      progress: _resume == null ? null : _resumePosition,
      dimension: item.dimension,
      extraArguments: {
        'storyFeed': true,
        'storyDiscovery': true,
        'storySeed': item,
        'storySessionId': _resume == null
            ? _session
            : 'discovery-${DateTime.now().microsecondsSinceEpoch}',
        'storyInitialItems': _resume == null ? items.toList() : null,
      },
    );
  }

  @override
  void animateToTop() {}

  @override
  void onInit() {
    super.onInit();
    onRefresh();
  }

  @override
  Future<void> onRefresh() =>
      _loadTask ??= _load(refresh: true).whenComplete(() => _loadTask = null);
  Future<void> loadMore() =>
      _loadTask ??= _load(refresh: false).whenComplete(() => _loadTask = null);

  Future<void> _load({required bool refresh}) async {
    if (loading.value || isClosed) return;
    loading.value = true;
    error.value = null;
    final page = refresh ? 1 : _page + 1;
    try {
      // Discovery supplies the first playable item and the initial feed batch.
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

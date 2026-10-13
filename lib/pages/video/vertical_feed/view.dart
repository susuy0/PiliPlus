import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/video/story.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/vertical_feed/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

typedef StoryPageLoader = FeedPageLoader<StoryVideoItem>;

class VerticalVideoFeed extends StatefulWidget {
  const VerticalVideoFeed({
    super.key,
    required this.seed,
    required this.loadPage,
    required this.onSwitch,
    required this.playerBuilder,
    required this.playerController,
    required this.introController,
    required this.onExit,
    required this.onDetails,
    this.onComments,
    this.isPipMode = false,
  });

  final StoryVideoItem seed;
  final StoryPageLoader loadPage;
  final Future<bool> Function(StoryVideoItem item) onSwitch;
  final WidgetBuilder playerBuilder;
  final PlPlayerController playerController;
  final UgcIntroController introController;
  final VoidCallback onExit;
  final VoidCallback onDetails;
  final VoidCallback? onComments;
  final bool isPipMode;

  @override
  State<VerticalVideoFeed> createState() => _VerticalVideoFeedState();
}

class _VerticalVideoFeedState extends State<VerticalVideoFeed> {
  final _pages = PageController();
  late final _feed = VerticalFeedController<StoryVideoItem>(
    seed: widget.seed,
    loadPage: widget.loadPage,
    idOf: (item) => item.aid!,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  late int _playingAid = widget.seed.aid!;
  bool _switching = false;
  bool _playbackError = false;
  double? _seekSeconds;
  late bool _paused = widget.playerController.playerStatus.isPaused;

  void _onPlayerStatus(PlayerStatus status) {
    if (mounted) setState(() => _paused = status.isPaused);
  }

  @override
  void initState() {
    super.initState();
    widget.playerController.addStatusLister(_onPlayerStatus);
    _feed.loadMore();
  }

  @override
  void dispose() {
    widget.playerController.removeStatusLister(_onPlayerStatus);
    _feed.dispose();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _activate(int index) async {
    if (!mounted || _switching || index >= _feed.items.length) return;
    final item = _feed.items[index];
    setState(() {
      _feed.index = index;
      _switching = true;
      _playbackError = false;
    });
    bool success;
    try {
      success = await widget.onSwitch(item);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      _switching = false;
      _playbackError = !success;
      if (success) _playingAid = item.aid!;
    });
    if (_feed.items.length - index <= 4) _feed.loadMore();
    _trimHistoryWhenIdle();
  }

  Future<void> _loadFromTail() async {
    final requestedIndex = _feed.index;
    await _feed.loadMore();
    if (!mounted) return;
    if (_feed.index == requestedIndex && requestedIndex < _feed.items.length) {
      await _activate(requestedIndex);
    }
  }

  void _onPageChanged(int index) {
    if (_switching) return;
    if (index == _feed.index && !_playbackError) return;
    if (index == _feed.items.length) {
      setState(() {
        _feed.index = index;
        _playbackError = false;
      });
      widget.playerController.pause();
      _loadFromTail();
    } else {
      _activate(index);
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification && !_switching) {
      _trimHistoryWhenIdle();
    }
    return false;
  }

  void _trimHistoryWhenIdle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _switching ||
          !_pages.hasClients ||
          _pages.position.isScrollingNotifier.value) {
        return;
      }
      final removed = _feed.trimHistory();
      if (removed > 0) {
        setState(() {});
        _pages.jumpToPage(_feed.index);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(offstage: widget.isPipMode, child: _buildFeed(context)),
      if (widget.isPipMode) widget.playerBuilder(context),
    ],
  );

  Widget _buildFeed(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            physics: _switching
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            itemCount: _feed.items.length + 1,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              if (index == _feed.items.length) return _tail();
              final item = _feed.items[index];
              final active = index == _feed.index;
              return Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => NetworkImgLayer(
                      src: item.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.contain,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  if (active &&
                      !widget.isPipMode &&
                      !_switching &&
                      !_playbackError &&
                      item.aid == _playingAid)
                    widget.playerBuilder(context),
                  if (active && _paused && !_switching && !_playbackError)
                    const Center(
                      child: IgnorePointer(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 80,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  if (active && _switching)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  if (active && _playbackError)
                    Center(
                      child: FilledButton.tonal(
                        onPressed: () => _activate(index),
                        child: const Text('播放失败，点击重试'),
                      ),
                    ),
                  _overlay(item, active && !_switching && !_playbackError),
                ],
              );
            },
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 8,
          child: IconButton(
            tooltip: '返回',
            onPressed: widget.onExit,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
      ],
    ),
  );

  Widget _tail() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_feed.loading)
          const CircularProgressIndicator(color: Colors.white)
        else
          TextButton.icon(
            onPressed: _loadFromTail,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: Text(
              _feed.error ?? '继续加载推荐视频',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        const SizedBox(height: 16),
        const Text('下滑可返回上一条', style: TextStyle(color: Colors.white70)),
      ],
    ),
  );

  Widget _overlay(StoryVideoItem item, bool active) => Obx(() {
    final intro = widget.introController;
    final detail = intro.videoDetail.value;
    final ready = active && detail.bvid == item.bvid;
    final owner = ready ? detail.owner : item.owner;
    final title = ready ? detail.title ?? item.title : item.title;
    final stat = ready ? detail.stat : null;
    final liked = intro.hasLike.value && ready;
    final favorited = intro.hasFav.value && ready;
    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 220,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 90,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _action(
                liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                NumUtils.numFormat(stat?.like ?? item.stat.like),
                ready ? () => intro.handleAction(intro.actionLikeVideo) : null,
                selected: liked,
              ),
              if (widget.onComments != null)
                _action(
                  Icons.chat_bubble_outline,
                  NumUtils.numFormat(stat?.reply),
                  ready ? widget.onComments : null,
                ),
              _action(
                favorited ? Icons.star : Icons.star_border,
                NumUtils.numFormat(stat?.favorite),
                ready
                    ? () => intro.handleAction(
                        () => intro.actionFavVideo(isQuick: true),
                      )
                    : null,
                selected: favorited,
              ),
              _action(
                Icons.share_outlined,
                '分享',
                ready ? () => intro.actionShareVideo(context) : null,
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 80,
          bottom: MediaQuery.paddingOf(context).bottom + 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (owner?.name?.isNotEmpty == true)
                InkWell(
                  onTap: ready && owner?.mid != null
                      ? () => Get.toNamed('/member?mid=${owner!.mid}')
                      : null,
                  child: Text(
                    '@${owner!.name}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: active ? widget.onDetails : null,
                child: const Text(
                  '详情  ›',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        if (active)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom,
            child: Obx(() {
              final total = widget.playerController.duration.value;
              final position = widget.playerController.position.value;
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 4,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: Slider(
                  min: 0,
                  max: total > 0 ? total.toDouble() : 1,
                  value: (_seekSeconds ?? position.toDouble())
                      .clamp(0, total > 0 ? total : 1)
                      .toDouble(),
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                  onChanged: total > 0
                      ? (value) => setState(() => _seekSeconds = value)
                      : null,
                  onChangeEnd: (value) {
                    widget.playerController.seekTo(
                      Duration(seconds: value.toInt()),
                    );
                    setState(() => _seekSeconds = null);
                  },
                ),
              );
            }),
          ),
      ],
    );
  });

  Widget _action(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? Colors.pinkAccent : Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

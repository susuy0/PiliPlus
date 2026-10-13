import 'package:PiliPlus/pages/video/vertical_feed/pager.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/common/design_tokens.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/pages/video/vertical_feed/viewport.dart';
import 'package:PiliPlus/pages/video/vertical_feed/panel_playback.dart';
import 'package:PiliPlus/pages/video/vertical_feed/action_button.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:flutter/services.dart';
import 'package:PiliPlus/models/video/story.dart';
import 'package:PiliPlus/models/model_owner.dart';
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
    this.commentsBuilder,
    required this.onMore,
    this.onPip,
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
  final WidgetBuilder? commentsBuilder;
  final VoidCallback onMore;
  final VoidCallback? onPip;
  final bool isPipMode;

  @override
  State<VerticalVideoFeed> createState() => _VerticalVideoFeedState();
}

class _VerticalVideoFeedState extends State<VerticalVideoFeed>
    with WidgetsBindingObserver {
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
  final _presentations =
      <
        int,
        ({
          VideoDetailData detail,
          bool liked,
          bool favorited,
          bool followed,
          int duration,
          int position,
        })
      >{};
  bool _switching = false;
  bool _playbackError = false;
  double? _seekSeconds;
  bool _commentsOpen = false;
  bool _commentsExpanded = false;
  bool _titleExpanded = false;
  double _sheetDragDistance = 0;
  bool _keyboardVisible = false;
  final _panelPlayback = PanelPlaybackPolicy();
  late final VideoFitType _originalFit;

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboard = View.of(context).viewInsets.bottom > 0;
    if (_keyboardVisible != keyboard) {
      _keyboardVisible = keyboard;
      _syncPanelPlayback();
      setState(() {});
    }
  }

  void _syncPanelPlayback() {
    switch (_panelPlayback.update(
      obscured: _commentsOpen && (_commentsExpanded || _keyboardVisible),
      playing: widget.playerController.playerStatus.isPlaying,
    )) {
      case PanelPlaybackAction.pause:
        widget.playerController.pause();
      case PanelPlaybackAction.resume:
        widget.playerController.play();
      case PanelPlaybackAction.none:
        break;
    }
  }

  void _closeComments() {
    setState(() {
      _commentsOpen = false;
      _commentsExpanded = false;
    });
    _syncPanelPlayback();
  }

  void _back() {
    if (_keyboardVisible) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } else if (_commentsOpen) {
      if (_commentsExpanded) {
        setState(() => _commentsExpanded = false);
        _syncPanelPlayback();
      } else {
        _closeComments();
      }
    } else if (_titleExpanded) {
      setState(() => _titleExpanded = false);
    } else {
      widget.onExit();
    }
  }

  late bool _paused = widget.playerController.playerStatus.isPaused;

  void _onPlayerStatus(PlayerStatus status) {
    if (mounted) setState(() => _paused = status.isPaused);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _originalFit = widget.playerController.videoFit.value;
    widget.playerController.videoFit.value = VideoFitType.contain;
    widget.playerController.addStatusLister(_onPlayerStatus);
    _feed.loadMore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.playerController.videoFit.value = _originalFit;
    widget.playerController.removeStatusLister(_onPlayerStatus);
    _feed.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _rememberCurrent() {
    if (_feed.index >= _feed.items.length) return;
    final item = _feed.items[_feed.index];
    final intro = widget.introController;
    final detail = intro.videoDetail.value;
    if (detail.bvid != item.bvid) return;
    _presentations[item.aid!] = (
      detail: detail,
      liked: intro.hasLike.value,
      favorited: intro.hasFav.value,
      followed: const {
        -10,
        1,
        2,
        4,
        6,
      }.contains(intro.followStatus.value.attribute),
      duration: widget.playerController.duration.value,
      position: widget.playerController.position.value,
    );
  }

  Future<void> _activate(int index) async {
    if (!mounted || _switching || index >= _feed.items.length) return;
    _rememberCurrent();
    final item = _feed.items[index];
    setState(() {
      _feed.index = index;
      _switching = true;
      _playbackError = false;
      _titleExpanded = false;
      _seekSeconds = null;
      widget.playerController.videoFit.value = VideoFitType.contain;
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

  void _onPageSettled(int index) {
    if (_switching) return;
    if (index == _feed.index && !_playbackError) return;
    if (index == _feed.items.length) {
      _rememberCurrent();
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
        final retained = _feed.items.map((item) => item.aid).toSet();
        _presentations.removeWhere((aid, _) => !retained.contains(aid));
        setState(() {});
        _pages.jumpToPage(_feed.index);
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: widget.isPipMode,
          child: Theme(
            data: ThemeUtils.darkTheme.copyWith(
              colorScheme: ThemeUtils.darkTheme.colorScheme.copyWith(
                surface: AppDesign.playerSheet,
                surfaceContainerLowest: AppDesign.playerSheet,
                primary: AppDesign.playerPrimary,
              ),
              scaffoldBackgroundColor: AppDesign.playerSheet,
            ),
            child: _buildFeed(context),
          ),
        ),
        if (widget.isPipMode) widget.playerBuilder(context),
      ],
    ),
  );

  Widget _buildFeed(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: FeedViewport(
      expanded: _commentsExpanded || _keyboardVisible,
      comments: _commentsOpen && widget.commentsBuilder != null
          ? MiniScaffold(body: Builder(builder: widget.commentsBuilder!))
          : null,
      sheetHeader: _commentHeader(),
      video: FeedPager(
        controller: _pages,
        enabled:
            !_switching &&
            !_commentsOpen &&
            _seekSeconds == null &&
            !_titleExpanded,
        itemCount: _feed.items.length + 1,
        onSettled: _onPageSettled,
        onDragStart: _rememberCurrent,
        itemBuilder: (context, index) {
          if (index == _feed.items.length) {
            return FeedPage(
              content: _tail(),
              controls: Stack(
                children: [
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    left: 8,
                    child: _topButton('返回', Icons.arrow_back_rounded, _back),
                  ),
                ],
              ),
            );
          }
          final item = _feed.items[index];
          final active = index == _feed.index;
          return FeedPage(
            key: ValueKey(item.aid),
            content: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, box) => NetworkImgLayer(
                    src: item.cover,
                    width: box.maxWidth,
                    height: box.maxHeight,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                if (active &&
                    !widget.isPipMode &&
                    !_switching &&
                    !_playbackError &&
                    item.aid == _playingAid)
                  FeedPlayerReveal(child: widget.playerBuilder(context)),
                if (active && _paused && !_switching && !_playbackError)
                  const Center(
                    child: IgnorePointer(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 72,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                if (active && _switching)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                if (active && _playbackError)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '这条视频暂时无法播放',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => _activate(index),
                          child: const Text('重新播放'),
                        ),
                        TextButton(
                          onPressed: _next,
                          child: const Text('跳过这一条'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            controls: _commentsOpen
                ? null
                : IgnorePointer(
                    ignoring: !active,
                    child: _pageControls(
                      item,
                      active,
                      active && !_switching && !_playbackError,
                    ),
                  ),
          );
        },
      ),
      controls: const SizedBox.shrink(),
    ),
  );

  Widget _pageControls(StoryVideoItem item, bool selected, bool ready) => Stack(
    children: [
      _overlay(item, ready),
      Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        left: 8,
        child: _topButton('返回', Icons.arrow_back_rounded, _back),
      ),
      if (widget.onPip != null)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 8,
          child: _topButton(
            '小窗播放',
            Icons.picture_in_picture_outlined,
            widget.onPip!,
          ),
        ),
      if (selected)
        Obx(
          () => widget.playerController.videoFit.value == VideoFitType.cover
              ? Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 64,
                  right: 64,
                  child: Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => widget.playerController.videoFit.value =
                          VideoFitType.contain,
                      icon: const Icon(Icons.fit_screen, size: 16),
                      label: const Text('已裁剪填充 · 还原'),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
    ],
  );

  Widget _topButton(String label, IconData icon, VoidCallback callback) =>
      IconButton(
        tooltip: label,
        onPressed: callback,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0x73000000),
          minimumSize: const Size(48, 48),
        ),
        icon: Icon(icon, color: Colors.white, size: 24),
      );

  Widget _commentHeader() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (_) => _sheetDragDistance = 0,
    onVerticalDragUpdate: (details) => _sheetDragDistance += details.delta.dy,
    onVerticalDragEnd: (details) {
      if (_sheetDragDistance > 80 || (details.primaryVelocity ?? 0) > 200) {
        if (_commentsExpanded) {
          setState(() => _commentsExpanded = false);
          _syncPanelPlayback();
        } else {
          _closeComments();
        }
      } else if (_sheetDragDistance < -80 ||
          (details.primaryVelocity ?? 0) < -200) {
        setState(() => _commentsExpanded = true);
        _syncPanelPlayback();
      }
    },
    child: Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  '评论',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: _commentsExpanded ? '收起评论' : '展开评论',
                onPressed: () {
                  setState(() => _commentsExpanded = !_commentsExpanded);
                  _syncPanelPlayback();
                },
                icon: Icon(
                  _commentsExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  color: Colors.white70,
                ),
              ),
              IconButton(
                tooltip: '关闭评论',
                onPressed: _closeComments,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _next() {
    if (_pages.hasClients) {
      _pages.nextPage(
        duration: AppDesign.motion(context),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _tail() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_feed.loading)
            const CircularProgressIndicator(color: Colors.white)
          else ...[
            const Icon(
              Icons.video_library_outlined,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              _feed.error ?? '暂时没有新的推荐',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadFromTail,
              child: const Text('重新加载'),
            ),
            TextButton(
              onPressed: widget.onDetails,
              child: const Text('返回视频详情'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            '下滑可返回上一条',
            style: TextStyle(color: AppDesign.playerMuted),
          ),
        ],
      ),
    ),
  );

  Widget _overlay(StoryVideoItem item, bool active) => Obx(() {
    final intro = widget.introController;
    final liveDetail = intro.videoDetail.value;
    final saved = _presentations[item.aid];
    final detail = liveDetail.bvid == item.bvid ? liveDetail : saved?.detail;
    final ready = active && liveDetail.bvid == item.bvid;
    final owner = detail?.owner ?? item.owner;
    final face =
        detail?.owner?.face ??
        (item.owner is Owner ? (item.owner as Owner).face : null);
    final title = detail?.title ?? item.title;
    final stat = detail?.stat;
    final liked = ready ? intro.hasLike.value : saved?.liked ?? false;
    final favorited = ready ? intro.hasFav.value : saved?.favorited ?? false;
    final followed = ready
        ? const {-10, 1, 2, 4, 6}.contains(intro.followStatus.value.attribute)
        : saved?.followed ?? item.isFollowed;
    final seeking = active && _seekSeconds != null;
    final safe = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: safe + 300,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: MediaQuery.paddingOf(context).top + 104,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        if (!seeking) ...[
          Positioned(
            right: 8,
            bottom: safe + 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _action(
                  liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                  NumUtils.numFormat(stat?.like ?? item.stat.like),
                  ready
                      ? () => intro.handleAction(intro.actionLikeVideo)
                      : null,
                  color: liked ? AppDesign.like : Colors.white,
                  semantics: liked ? '已点赞' : '点赞',
                  onStartTriple: ready
                      ? () => intro.handleAction(intro.onStartTriple)
                      : null,
                  onCancelTriple: ready ? intro.onCancelTriple : null,
                  tripleAnimation: ready ? intro.tripleAnimation : null,
                ),
                if (widget.commentsBuilder != null)
                  _action(
                    Icons.chat_bubble_outline_rounded,
                    NumUtils.numFormat(stat?.reply),
                    ready
                        ? () => setState(() {
                            _commentsOpen = true;
                            _titleExpanded = false;
                          })
                        : null,
                    semantics: '评论',
                  ),
                _action(
                  favorited ? Icons.star_rounded : Icons.star_border_rounded,
                  NumUtils.numFormat(stat?.favorite),
                  ready
                      ? () => intro.handleAction(
                          () => intro.actionFavVideo(isQuick: true),
                        )
                      : null,
                  color: favorited ? AppDesign.favorite : Colors.white,
                  semantics: favorited ? '已收藏' : '收藏',
                  onLongPress: ready
                      ? () => intro.handleAction(intro.actionFavVideo)
                      : null,
                ),
                _action(
                  Icons.reply_rounded,
                  '分享',
                  ready ? () => intro.actionShareVideo(context) : null,
                  semantics: '分享',
                ),
                _action(
                  Icons.more_vert_rounded,
                  '更多',
                  ready ? widget.onMore : null,
                  semantics: '更多操作',
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 84,
            bottom: safe + 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (owner.name?.isNotEmpty == true)
                  Row(
                    children: [
                      if (face?.isNotEmpty == true) ...[
                        InkWell(
                          onTap: ready
                              ? () => Get.toNamed('/member?mid=${owner.mid}')
                              : null,
                          child: NetworkImgLayer(
                            src: face,
                            type: .avatar,
                            width: 36,
                            height: 36,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: InkWell(
                          onTap: ready
                              ? () => Get.toNamed('/member?mid=${owner.mid}')
                              : null,
                          child: Text(
                            owner.name!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.375,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: ready
                            ? () => intro.actionRelationMod(context)
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: followed
                              ? Colors.white
                              : AppDesign.playerPrimary,
                          backgroundColor: followed
                              ? Colors.white12
                              : const Color(0xFF5E1633),
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(
                          followed ? '已关注' : '+ 关注',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() => _titleExpanded = !_titleExpanded),
                  child: active && _titleExpanded
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: SingleChildScrollView(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.47,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.47,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: active ? widget.onDetails : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppDesign.playerMuted,
                    backgroundColor: const Color(0x73000000),
                    minimumSize: const Size(48, 48),
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 16),
                  label: const Text('视频详情', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
        if (seeking)
          Center(
            child: Text(
              '${DurationUtils.formatDuration(_seekSeconds!.toInt())} / ${DurationUtils.formatDuration(widget.playerController.duration.value)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: safe,
          child: Obx(() {
            final total = active
                ? widget.playerController.duration.value
                : saved?.duration ?? item.duration;
            final position = active
                ? widget.playerController.position.value
                : saved?.position ?? 0;
            return SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: _paused || seeking ? 4 : 2,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: seeking ? 6 : 0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 16,
                ),
              ),
              child: SizedBox(
                height: 48,
                child: Slider(
                  min: 0,
                  max: total > 0 ? total.toDouble() : 1,
                  value: ((active ? _seekSeconds : null) ?? position.toDouble())
                      .clamp(0, total > 0 ? total : 1)
                      .toDouble(),
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                  onChangeStart: active && total > 0
                      ? (value) => setState(() => _seekSeconds = value)
                      : null,
                  onChanged: active && total > 0
                      ? (value) => setState(() => _seekSeconds = value)
                      : null,
                  onChangeEnd: active
                      ? (value) {
                          widget.playerController.seekTo(
                            Duration(seconds: value.toInt()),
                          );
                          setState(() => _seekSeconds = null);
                        }
                      : null,
                ),
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
    Color color = Colors.white,
    required String semantics,
    VoidCallback? onLongPress,
    VoidCallback? onStartTriple,
    void Function([bool])? onCancelTriple,
    Animation<double>? tripleAnimation,
  }) => FeedActionButton(
    icon: icon,
    label: label,
    onTap: onTap,
    color: color,
    semantics: semantics,
    onLongPress: onLongPress,
    onStartTriple: onStartTriple,
    onCancelTriple: onCancelTriple,
    tripleAnimation: tripleAnimation,
  );
}

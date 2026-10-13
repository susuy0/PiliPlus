import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/pages/video/vertical_feed/desktop.dart';
import 'package:PiliPlus/pages/video/vertical_feed/cover.dart';
import 'package:PiliPlus/pages/video/vertical_feed/chrome.dart';
import 'package:PiliPlus/pages/video/vertical_feed/follow_button.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:window_manager/window_manager.dart';
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
    this.onPreload,
    this.onCancelPreload,
    this.author,
    this.authorLoader,
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
  final Future<bool> Function(StoryVideoItem)? onPreload;
  final VoidCallback? onCancelPreload;
  final Owner? author;
  final StoryPageLoader Function(Owner owner, StoryVideoItem seed)?
  authorLoader;

  @override
  State<VerticalVideoFeed> createState() => _VerticalVideoFeedState();
}

class _VerticalVideoFeedState extends State<VerticalVideoFeed>
    with WidgetsBindingObserver {
  final _pages = PageController();
  final _wheelGate = FeedWheelGate();
  bool _pipBusy = false;
  Timer? _preloadTimer;
  StreamSubscription<List<ConnectivityResult>>? _preloadNetwork;
  int? _preloadAid;
  bool _warming = false;
  bool _foreground = true;
  DateTime _preloadRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pipWasFullscreen = false;
  ({bool comments, bool expanded, bool title})? _pipPanels;
  bool get _desktopPip =>
      PlatformUtils.isDesktop && widget.playerController.isDesktopPip;
  bool get _systemPip => widget.isPipMode && !PlatformUtils.isDesktop;
  bool get _canNavigate =>
      !_switching &&
      (_desktopPip || (!_commentsOpen && !_titleExpanded)) &&
      _seekSeconds == null;
  late var _feed = VerticalFeedController<StoryVideoItem>(
    seed: widget.seed,
    loadPage: widget.loadPage,
    idOf: (item) => item.aid!,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  VerticalFeedController<StoryVideoItem>? _returnFeed;
  int _returnPosition = 0;
  late Owner? _author = widget.author;
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
  final _relations = <int, int>{};
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
    if (_switching && _returnFeed == null) {
      widget.onExit();
      return;
    }
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
    } else if (_returnFeed != null) {
      _leaveAuthorFeed();
    } else {
      widget.onExit();
    }
  }

  void _openAuthorFeed(Owner owner) {
    if (_switching ||
        _author != null ||
        owner.mid == null ||
        owner.mid! <= 0 ||
        widget.authorLoader == null ||
        _feed.index >= _feed.items.length)
      return;
    _rememberCurrent();
    _stopPreload();
    final seed = _feed.items[_feed.index];
    _returnPosition = widget.playerController.position.value;
    _returnFeed = _feed;
    setState(() {
      _author = owner;
      _titleExpanded = false;
      _playbackError = false;
      _feed = VerticalFeedController<StoryVideoItem>(
        seed: seed,
        loadPage: widget.authorLoader!(owner, seed),
        idOf: (item) => item.aid!,
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    _feed.loadMore();
  }

  Future<void> _leaveAuthorFeed() async {
    final previous = _returnFeed;
    if (previous == null) return;
    _stopPreload();
    final authorFeed = _feed;
    final target = previous.items[previous.index];
    final position = _returnPosition;
    setState(() {
      _feed = previous;
      _returnFeed = null;
      _author = widget.author;
      _switching = true;
      _playbackError = false;
    });
    authorFeed.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) _pages.jumpToPage(previous.index);
    });
    var success = widget.playerController.bvid == target.bvid;
    try {
      if (!success) {
        success = await widget.onSwitch(target);
        if (success && mounted && position > 0)
          await widget.playerController.seekTo(
            Duration(seconds: position),
            isSeek: false,
          );
      }
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      _switching = false;
      _playbackError = !success;
      if (success) _playingAid = target.aid!;
    });
  }

  late bool _paused = widget.playerController.playerStatus.isPaused;

  void _onPlayerStatus(PlayerStatus status) {
    if (!mounted) return;
    setState(() => _paused = status.isPaused);
    if (status.isPaused && !_switching && _ownsPlayback) {
      _stopPreload();
    }
    if (status.isPlaying) _preloadNext();
  }

  bool get _ownsPlayback =>
      widget.playerController.videoPlayerController != null &&
      _feed.index < _feed.items.length &&
      widget.playerController.bvid == _feed.items[_feed.index].bvid;

  void _stopPreload() {
    _preloadAid = null;
    widget.onCancelPreload?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stopPreload();
  }

  @override
  void didHaveMemoryPressure() => _stopPreload();

  Future<void> _preloadNext() async {
    if (Pref.storyPreloadMode == 0) {
      if (_preloadAid != null || _warming) _stopPreload();
      return;
    }
    if (!mounted ||
        !_foreground ||
        _systemPip ||
        _switching ||
        !_ownsPlayback ||
        widget.onPreload == null ||
        _feed.index + 1 >= _feed.items.length)
      return;
    final player = widget.playerController;
    if (!player.playerStatus.isPlaying ||
        player.isBuffering.value ||
        (player.buffered.value - player.position.value < 1 &&
            !(player.duration.value > 0 &&
                player.buffered.value >= player.duration.value))) {
      if (_warming) {
        _stopPreload();
        _preloadRetryAt = DateTime.now().add(const Duration(seconds: 15));
      }
      return;
    }
    final next = _feed.items[_feed.index + 1];
    if (_warming ||
        _preloadAid == next.aid ||
        DateTime.now().isBefore(_preloadRetryAt))
      return;
    _preloadAid = next.aid;
    _warming = true;
    bool ready;
    try {
      ready = await widget.onPreload!(next);
    } catch (_) {
      ready = false;
    } finally {
      _warming = false;
    }
    if (!ready && _preloadAid == next.aid) {
      _preloadAid = null;
      _preloadRetryAt = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _originalFit = widget.playerController.videoFit.value;
    widget.playerController.videoFit.value = VideoFitType.contain;
    widget.playerController.addStatusLister(_onPlayerStatus);
    _feed.loadMore();
    _preloadTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _preloadNext(),
    );
    if (widget.onPreload != null) {
      _preloadNetwork = Connectivity().onConnectivityChanged.listen((network) {
        _preloadRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
        if (Pref.storyPreloadMode == 1 &&
            !network.any(
              (e) =>
                  e == ConnectivityResult.wifi ||
                  e == ConnectivityResult.ethernet,
            )) {
          _stopPreload();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preloadTimer?.cancel();
    _preloadNetwork?.cancel();
    widget.onCancelPreload?.call();
    widget.playerController.videoFit.value = _originalFit;
    widget.playerController.removeStatusLister(_onPlayerStatus);
    _feed.dispose();
    _returnFeed?.dispose();
    _wheelGate.dispose();
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
      followed: intro.followStatus.value.attribute == null
          ? item.isFollowed
          : const {
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
    final sourceFeed = _feed;
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
    if (!mounted || !identical(_feed, sourceFeed)) return;
    setState(() {
      _switching = false;
      _playbackError = !success;
      if (success) _playingAid = item.aid!;
    });
    if (_feed.items.length - index <= 4) _feed.loadMore();
    _trimHistoryWhenIdle();
  }

  Future<void> _loadFromTail() async {
    final sourceFeed = _feed;
    final requestedIndex = _feed.index;
    await _feed.loadMore();
    if (!mounted || !identical(_feed, sourceFeed)) return;
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
        final owners = {
          for (final item in _feed.items) item.owner.mid,
          for (final presentation in _presentations.values)
            presentation.detail.owner?.mid,
        };
        _relations.removeWhere((mid, _) => !owners.contains(mid));
        setState(() {});
        _pages.jumpToPage(_feed.index);
      }
    });
  }

  void _turn(int direction) {
    if (!_canNavigate ||
        !_pages.hasClients ||
        _pages.position.isScrollingNotifier.value)
      return;
    final index = ((_pages.page ?? _feed.index.toDouble()).round() + direction)
        .clamp(0, _feed.items.length);
    _pages.animateToPage(
      index,
      duration: AppDesign.motion(context, 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _togglePip() async {
    if (_pipBusy ||
        _switching ||
        widget.playerController.videoPlayerController == null)
      return;
    _pipBusy = true;
    final player = widget.playerController;
    try {
      if (player.isDesktopPip) {
        await player.exitDesktopPip();
        if (!mounted) return;
        final panels = _pipPanels;
        setState(() {
          _commentsOpen = panels?.comments ?? false;
          _commentsExpanded = panels?.expanded ?? false;
          _titleExpanded = panels?.title ?? false;
          _pipPanels = null;
        });
        if (_pipWasFullscreen) await player.triggerFullScreen();
      } else {
        _pipWasFullscreen = player.isFullScreen.value;
        _pipPanels = (
          comments: _commentsOpen,
          expanded: _commentsExpanded,
          title: _titleExpanded,
        );
        setState(() {
          _commentsOpen = false;
          _commentsExpanded = false;
          _titleExpanded = false;
        });
        _syncPanelPlayback();
        if (player.isFullScreen.value)
          await player.triggerFullScreen(status: false);
        await player.enterDesktopPip();
        if (mounted) setState(() {});
      }
      _syncPanelPlayback();
    } finally {
      _pipBusy = false;
    }
  }

  Future<void> _openComments() async {
    if (_desktopPip) {
      if (_pipBusy) return;
      await _togglePip();
      if (!mounted || _desktopPip) return;
    }
    if (widget.commentsBuilder == null) return;
    setState(() {
      _commentsOpen = true;
      _titleExpanded = false;
    });
    _syncPanelPlayback();
  }

  void _seekDesktop(int seconds) {
    final player = widget.playerController;
    final state = player.videoPlayerController?.state;
    if (state == null) return;
    player.seekTo(
      Duration(
        milliseconds: (state.position.inMilliseconds + seconds * 1000)
            .clamp(0, state.duration.inMilliseconds)
            .toInt(),
      ),
      isSeek: false,
    );
  }

  void _desktopCommand(FeedCommand command) {
    final player = widget.playerController;
    final ready =
        !_switching &&
        !_playbackError &&
        _feed.index < _feed.items.length &&
        widget.introController.videoDetail.value.bvid ==
            _feed.items[_feed.index].bvid;
    switch (command) {
      case FeedCommand.previous:
        _turn(-1);
      case FeedCommand.next:
        _turn(1);
      case FeedCommand.playPause:
        if (ready && player.videoPlayerController != null)
          player.onDoubleTapCenter();
      case FeedCommand.backward:
        if (ready) _seekDesktop(-10);
      case FeedCommand.forward:
        if (ready) _seekDesktop(10);
      case FeedCommand.volumeUp:
        player.setVolume((player.volume.value + .1).clamp(0, player.maxVolume));
      case FeedCommand.volumeDown:
        player.setVolume((player.volume.value - .1).clamp(0, player.maxVolume));
      case FeedCommand.mute:
        if (player.videoPlayerController != null) {
          player.isMuted = !player.isMuted;
          player.videoPlayerController!.setVolume(
            player.isMuted ? 0 : player.volume.value * 100,
          );
        }
      case FeedCommand.fullscreen:
        if (_desktopPip) {
          _pipWasFullscreen = true;
          _togglePip();
        } else {
          player.triggerFullScreen(status: !player.isFullScreen.value);
        }
      case FeedCommand.pip:
        _togglePip();
      case FeedCommand.comments:
        if (ready) {
          if (_commentsOpen)
            _closeComments();
          else
            _openComments();
        }
      case FeedCommand.like:
        if (ready)
          widget.introController.handleAction(
            widget.introController.actionLikeVideo,
          );
      case FeedCommand.favorite:
        if (ready)
          widget.introController.handleAction(
            () => widget.introController.actionFavVideo(isQuick: true),
          );
      case FeedCommand.more:
        if (ready) widget.onMore();
      case FeedCommand.details:
        widget.onDetails();
      case FeedCommand.help:
        _showDesktopHelp();
      case FeedCommand.back:
        if (_desktopPip)
          _togglePip();
        else if (!_commentsOpen && !_titleExpanded && player.isFullScreen.value)
          player.triggerFullScreen(status: false);
        else
          _back();
    }
  }

  void _showDesktopHelp() => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('连续观看快捷键'),
      content: const SingleChildScrollView(
        child: Text(
          '↑ / ↓ 或 PageUp / PageDown：上一条 / 下一条\n滚轮：切换视频；触控板：跟手翻页\n空格：播放 / 暂停\n← / →：后退 / 快进 10 秒\nShift + ↑ / ↓：音量加 / 减\nM：静音    F：全屏    P：小窗\nC：评论    L：点赞    E：收藏\nO：更多    V：视频详情    H：快捷键\nEsc：收起面板、还原窗口或退出\n输入文字时不触发上述快捷键',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Widget _desktopFrame(BuildContext context) {
    final feed = _buildFeed(context);
    return FeedDesktopInput(
      keyboardEnabled: widget.playerController.keyboardControl,
      navigationEnabled: _canNavigate,
      onCommand: _desktopCommand,
      child: FeedDesktopFrame(enabled: !_desktopPip, child: feed),
    );
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
          offstage: _systemPip,
          child: Theme(
            data: ThemeUtils.darkTheme.copyWith(
              colorScheme: ThemeUtils.darkTheme.colorScheme.copyWith(
                surface: AppDesign.playerSheet,
                surfaceContainerLowest: AppDesign.playerSheet,
                primary: AppDesign.playerPrimary,
              ),
              scaffoldBackgroundColor: AppDesign.playerSheet,
            ),
            child: PlatformUtils.isDesktop
                ? _desktopFrame(context)
                : _buildFeed(context),
          ),
        ),
        if (_systemPip) widget.playerBuilder(context),
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
      video: _wrapWheel(
        FeedPager(
          desktop: PlatformUtils.isDesktop,
          controller: _pages,
          enabled: _canNavigate,
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
                      top: FeedChrome.navigationTop(context),
                      left: 8,
                      child: _topButton(
                        _author == null ? '返回' : '退出UP主视频',
                        Icons.arrow_back_rounded,
                        _back,
                      ),
                    ),
                  ],
                ),
              );
            }
            final item = _feed.items[index];
            final active = index == _feed.index;
            final page = FeedPage(
              key: ValueKey(item.aid),
              content: Stack(
                fit: StackFit.expand,
                children: [
                  FeedCover(src: item.cover),
                  if (active &&
                      !_systemPip &&
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
            return page;
          },
        ),
      ),
      controls: const SizedBox.shrink(),
    ),
  );

  Widget _wrapWheel(Widget child) => PlatformUtils.isDesktop
      ? FeedWheelRegion(
          gate: _wheelGate,
          enabled: _canNavigate,
          onTurn: _turn,
          child: child,
        )
      : child;

  Widget _pageControls(StoryVideoItem item, bool selected, bool ready) =>
      _desktopPip
      ? _pipControls(item)
      : Stack(
          children: [
            _overlay(item, ready),
            Positioned(
              top: FeedChrome.navigationTop(context),
              left: 8,
              child: _topButton(
                _author == null ? '返回' : '退出UP主视频',
                Icons.arrow_back_rounded,
                _back,
              ),
            ),
            if (_author != null && !PlatformUtils.isDesktop)
              Positioned(
                top: FeedChrome.navigationTop(context) + 14,
                left: 64,
                right: 64,
                child: Text(
                  '${_author!.name ?? 'UP主'}的视频',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            if (PlatformUtils.isDesktop || widget.onPip != null)
              Positioned(
                top: FeedChrome.navigationTop(context),
                right: 8,
                child: _topButton(
                  '小窗播放',
                  Icons.picture_in_picture_outlined,
                  PlatformUtils.isDesktop ? _togglePip : widget.onPip!,
                ),
              ),
            if (PlatformUtils.isDesktop)
              Positioned(
                top: FeedChrome.navigationTop(context),
                left: 64,
                right: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _topButton(
                      '上一条 · ↑',
                      Icons.keyboard_arrow_up,
                      () => _turn(-1),
                    ),
                    _topButton(
                      '下一条 · ↓',
                      Icons.keyboard_arrow_down,
                      () => _turn(1),
                    ),
                    _topButton(
                      '全屏 · F',
                      Icons.fullscreen,
                      () => _desktopCommand(FeedCommand.fullscreen),
                    ),
                    _topButton(
                      '快捷键 · H',
                      Icons.keyboard_outlined,
                      _showDesktopHelp,
                    ),
                  ],
                ),
              ),
            if (selected)
              Obx(
                () =>
                    widget.playerController.videoFit.value == VideoFitType.cover
                    ? Positioned(
                        top: FeedChrome.navigationTop(context),
                        left: 64,
                        right: 64,
                        child: Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                widget.playerController.videoFit.value =
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

  Widget _pipControls(StoryVideoItem item) => Stack(
    children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: ColoredBox(
          color: Colors.black54,
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Obx(
                () => _pipButton(
                  widget.playerController.isAlwaysOnTop.value ? '取消置顶' : '窗口置顶',
                  Icons.push_pin_outlined,
                  () => widget.playerController.setAlwaysOnTop(
                    !widget.playerController.isAlwaysOnTop.value,
                  ),
                ),
              ),
              _pipButton('还原窗口 · P / Esc', Icons.open_in_full, _togglePip),
            ],
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: ColoredBox(
          color: Colors.black54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pipButton('上一条 · ↑', Icons.skip_previous, () => _turn(-1)),
              _pipButton(
                _paused ? '播放 · 空格' : '暂停 · 空格',
                _paused ? Icons.play_arrow : Icons.pause,
                () => _desktopCommand(FeedCommand.playPause),
              ),
              _pipButton('下一条 · ↓', Icons.skip_next, () => _turn(1)),
              _pipButton(
                '静音 · M',
                Icons.volume_off_outlined,
                () => _desktopCommand(FeedCommand.mute),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _pipButton(String tooltip, IconData icon, VoidCallback action) =>
      IconButton(
        tooltip: tooltip,
        onPressed: action,
        icon: Icon(icon, color: Colors.white, size: 20),
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
      );

  Widget _topButton(String label, IconData icon, VoidCallback callback) =>
      IconButton(
        tooltip: label,
        onPressed: callback,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0x73000000),
          minimumSize: const Size(
            FeedChrome.buttonExtent,
            FeedChrome.buttonExtent,
          ),
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
              onPressed: _feed.ended ? _back : _loadFromTail,
              child: Text(_feed.ended ? '退出UP主视频' : '重新加载'),
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
    final currentAttribute = ready ? intro.followStatus.value.attribute : null;
    if (currentAttribute != null && owner.mid != null) {
      _relations[owner.mid!] = currentAttribute;
    }
    final attribute = currentAttribute ?? _relations[owner.mid];
    final followed = attribute != null
        ? const {-10, 1, 2, 4, 6}.contains(attribute)
        : saved?.followed ?? item.isFollowed;
    final self = intro.isLogin && owner.mid == Accounts.main.mid;
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
          height: FeedChrome.safeTop(context) + 104,
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
                    ready ? _openComments : null,
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
                      Flexible(
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
                      if (!self) ...[
                        const SizedBox(width: 8),
                        FeedFollowButton(
                          key: ValueKey(owner.mid),
                          followed: followed,
                          attribute: attribute,
                          onPressed: ready
                              ? () => intro.actionRelationMod(
                                  context,
                                  isFollow: followed,
                                )
                              : null,
                        ),
                      ],
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
                if (_author == null &&
                    widget.authorLoader != null &&
                    owner.mid != null)
                  TextButton.icon(
                    onPressed: ready
                        ? () => _openAuthorFeed(
                            Owner(mid: owner.mid, name: owner.name, face: face),
                          )
                        : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppDesign.playerMuted,
                    ),
                    icon: const Icon(Icons.video_library_outlined, size: 16),
                    label: const Text('UP主视频', style: TextStyle(fontSize: 12)),
                  ),
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
            final controller = widget.playerController;
            final primary = ColorScheme.of(context).primary;
            return SizedBox(
              height: 48,
              child: ProgressBar(
                progress: (active ? controller.progress : position).clamp(
                  0,
                  total > 0 ? total : 0,
                ),
                buffered: active ? controller.buffered.value : 0,
                total: total > 0 ? total : 0,
                progressBarColor: primary,
                baseBarColor: const Color(0x33FFFFFF),
                bufferedBarColor: primary.withValues(alpha: .4),
                thumbColor: primary,
                thumbGlowColor: primary.withAlpha(80),
                barHeight: 3.5,
                thumbRadius: 7,
                thumbGlowRadius: 25,
                onDragStart: active && total > 0
                    ? (details) {
                        feedBack();
                        controller.onSeekStart(details.seconds);
                        setState(
                          () => _seekSeconds = details.seconds.toDouble(),
                        );
                      }
                    : null,
                onDragUpdate: active && total > 0
                    ? (details) {
                        if (!controller.isFileSource &&
                            controller.showSeekPreview)
                          controller.updatePreviewIndex(details.seconds);
                        controller.seekPosition.value = details.seconds;
                        setState(
                          () => _seekSeconds = details.seconds.toDouble(),
                        );
                      }
                    : null,
                onDragEnd: active
                    ? () {
                        controller.onSeekEnd();
                        if (mounted) setState(() => _seekSeconds = null);
                      }
                    : null,
                onSeek: active && total > 0
                    ? (milliseconds) {
                        controller
                          ..position.value = milliseconds ~/ 1000
                          ..onSeekEnd()
                          ..seekTo(
                            Duration(milliseconds: milliseconds),
                            isSeek: false,
                          );
                        if (mounted) setState(() => _seekSeconds = null);
                      }
                    : null,
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
    compact: PlatformUtils.isDesktop && MediaQuery.sizeOf(context).height < 640,
  );
}

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
import 'package:PiliPlus/pages/video/vertical_feed/story_layout.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/pages/video/vertical_feed/video_surface.dart';
import 'package:PiliPlus/pages/video/vertical_feed/progress_region.dart';
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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
    this.onMoreActions,
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
  final void Function(VoidCallback, VoidCallback?)? onMoreActions;
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
  bool _clean = false;
  bool _cinema = false;
  bool _cinemaBusy = false;
  Timer? _preloadTimer;
  StreamSubscription<List<ConnectivityResult>>? _preloadNetwork;
  int? _preloadAid;
  DateTime _preloadExpires = DateTime.fromMillisecondsSinceEpoch(0);
  bool _warming = false;
  bool _foreground = true;
  DateTime _preloadRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pipWasFullscreen = false;
  ({bool comments, bool expanded, bool title, bool cinema})? _pipPanels;
  bool get _desktopPip =>
      PlatformUtils.isDesktop && widget.playerController.isDesktopPip;
  bool get _systemPip => widget.isPipMode && !PlatformUtils.isDesktop;
  bool get _canNavigate =>
      !_switching &&
      !_cinema &&
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

  Future<void> _toggleCinema() async {
    if (_cinemaBusy || _switching || _desktopPip) return;
    _cinemaBusy = true;
    final enabled = !_cinema;
    widget.playerController.feedCinemaMode = enabled;
    setState(() {
      _cinema = enabled;
      _titleExpanded = false;
      if (enabled) {
        _commentsOpen = false;
        _commentsExpanded = false;
      }
    });
    _syncPanelPlayback();
    try {
      if (PlatformUtils.isMobile) {
        if (enabled) {
          await landscapeLeftMode();
        } else {
          await portraitUpMode();
        }
      } else {
        await widget.playerController.triggerFullScreen(status: enabled);
      }
    } finally {
      _cinemaBusy = false;
    }
  }

  void _back() {
    if (_cinema) {
      _toggleCinema();
      return;
    }
    if (_clean) {
      setState(() => _clean = false);
      return;
    }
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
    final wasSwitching = _switching;
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
    // A pending UP load may still replace the current player after exit.
    var success = !wasSwitching && widget.playerController.bvid == target.bvid;
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
        _preloadRetryAt = DateTime.now().add(const Duration(seconds: 2));
      }
      return;
    }
    final next = _feed.items[_feed.index + 1];
    if (_warming ||
        (_preloadAid == next.aid && DateTime.now().isBefore(_preloadExpires)) ||
        DateTime.now().isBefore(_preloadRetryAt))
      return;
    _preloadAid = next.aid;
    unawaited(FeedCover.prefetch(context, next.cover));
    _warming = true;
    bool ready;
    try {
      ready = await widget.onPreload!(next);
    } catch (_) {
      ready = false;
    } finally {
      _warming = false;
    }
    if (ready && _preloadAid == next.aid) {
      _preloadExpires = DateTime.now().add(const Duration(minutes: 4));
    }
    if (!ready && _preloadAid == next.aid) {
      _preloadAid = null;
      _preloadRetryAt = DateTime.now().add(const Duration(seconds: 3));
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
    widget.playerController.feedCinemaMode = false;
    if (_cinema && PlatformUtils.isMobile) portraitUpMode();
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
    if (intro.userStat.value.card?.mid == detail.owner?.mid.toString()) {
      item.followers = intro.userStat.value.follower;
    }
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
    if (!mounted || _switching || index < 0 || index >= _feed.items.length)
      return;
    _rememberCurrent();
    widget.playerController.beginFeedSwitch();
    _preloadRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
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
    if (success) _preloadNext();
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
          _cinema = panels?.cinema ?? false;
          player.feedCinemaMode = _cinema;
          _pipPanels = null;
        });
        if (_pipWasFullscreen) await player.triggerFullScreen();
      } else {
        _pipWasFullscreen = player.isFullScreen.value;
        _pipPanels = (
          comments: _commentsOpen,
          expanded: _commentsExpanded,
          title: _titleExpanded,
          cinema: _cinema,
        );
        setState(() {
          _commentsOpen = false;
          _commentsExpanded = false;
          _titleExpanded = false;
          _cinema = false;
          player.feedCinemaMode = false;
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
          _toggleCinema();
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
        if (ready) _showMore();
      case FeedCommand.details:
        widget.onDetails();
      case FeedCommand.help:
        _showDesktopHelp();
      case FeedCommand.back:
        if (_cinema)
          _back();
        else if (_desktopPip)
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
      child: FeedDesktopFrame(enabled: !_desktopPip && !_cinema, child: feed),
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

  Widget _buildFeed(BuildContext context) => Material(
    color: Colors.black,
    child: FeedViewport(
      expanded: _commentsExpanded || _keyboardVisible,
      comments: _commentsOpen && widget.commentsBuilder != null
          ? MiniScaffold(body: Builder(builder: widget.commentsBuilder!))
          : null,
      sheetHeader: _commentHeader(),
      video: Stack(
        fit: StackFit.expand,
        children: [
          _wrapWheel(
            FeedPager(
              desktop: PlatformUtils.isDesktop,
              controller: _pages,
              enabled: _canNavigate,
              itemCount: _feed.items.length + 1,
              onSettled: _onPageSettled,
              onDragStart: _rememberCurrent,
              itemBuilder: (context, index) {
                if (index == _feed.items.length) {
                  return FeedPage(content: _tail());
                }
                final item = _feed.items[index];
                final active = index == _feed.index;
                return FeedPage(
                  key: ValueKey(item.aid),
                  content: _overlay(item, active),
                  controls: _desktopPip ? _pipControls(item) : null,
                );
              },
            ),
          ),
          if (!_desktopPip && !_cinema) _navigation(),
          if (_cinema)
            Positioned(
              left: 8,
              top: FeedChrome.safeTop(context) + 4,
              child: _topButton(
                '返回竖屏',
                Icons.arrow_back_ios_new_rounded,
                _back,
              ),
            ),
        ],
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

  void _showMore() {
    final onPip = PlatformUtils.isDesktop ? _togglePip : widget.onPip;
    if (widget.onMoreActions case final show?) {
      show(
        () => setState(() {
          _clean = !_clean;
          _titleExpanded = false;
        }),
        onPip,
      );
    } else {
      widget.onMore();
    }
  }

  Widget _navigation() => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: EdgeInsets.only(top: FeedChrome.safeTop(context) + 4),
        child: Row(
          children: [
            _topButton(
              _cinema
                  ? '返回竖屏'
                  : _author == null
                  ? '返回'
                  : '退出UP主视频',
              Icons.arrow_back_ios_new_rounded,
              _back,
            ),
            Expanded(
              child: _cinema
                  ? const SizedBox.shrink()
                  : Obx(() {
                      final detail = widget.introController.videoDetail.value;
                      final count = widget.introController.total.value;
                      final countBvid = widget.introController.totalBvid.value;
                      return Text(
                        _author != null
                            ? '${_author!.name ?? 'UP主'}的视频'
                            : detail.bvid == widget.playerController.bvid &&
                                  widget.introController.isShowOnlineTotal &&
                                  countBvid == widget.playerController.bvid
                            ? '$count人正在看'
                            : '连续播放',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      );
                    }),
            ),
            if (!_cinema) ...[
              _topButton('搜索', Icons.search, () => Get.toNamed('/search')),
              if (PlatformUtils.isDesktop)
                _topButton(
                  '快捷键 · H',
                  Icons.keyboard_outlined,
                  _showDesktopHelp,
                ),
              _topButton('更多操作', Icons.more_vert, _showMore),
              if (PlatformUtils.isDesktop || widget.onPip != null)
                _topButton(
                  '小窗播放',
                  Icons.picture_in_picture_outlined,
                  PlatformUtils.isDesktop ? _togglePip : widget.onPip!,
                ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _videoContent(StoryVideoItem item, bool active) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FeedCover(src: item.cover),
        if (active && !_systemPip && !_playbackError)
          Obx(() {
            final frameReady = widget.playerController.feedFrameReady.value;
            final buffering = widget.playerController.isBuffering.value;
            final ready = !_switching && item.aid == _playingAid && frameReady;
            return FeedVideoSurface(
              video: FeedPlayerReveal(
                child: widget.playerBuilder(context),
              ),
              preview: FeedCover(src: item.cover),
              ready: ready,
              pending: !ready || buffering,
            );
          }),
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
                  onPressed: () => _activate(_feed.items.indexOf(item)),
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
    );
  }

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
    final labels = <String>{
      ...item.contentLabels,
      ...?detail?.contentLabels,
      if (detail?.isUpowerExclusive == true) '充电专属',
    }.toList();
    final followers =
        ready &&
            intro.userStat.value.card?.mid.toString() == owner.mid.toString()
        ? intro.userStat.value.follower
        : item.followers;
    final minimal = _commentsOpen || _desktopPip || _cinema;
    return IgnorePointer(
      ignoring: !active || _switching,
      child: FeedStoryLayout(
        topInset: _desktopPip || _cinema
            ? 0
            : FeedChrome.navigationTop(context) + FeedChrome.buttonExtent + 4,
        bottomInset: minimal ? 0 : safe,
        clean: _clean || minimal,
        video: Stack(
          fit: StackFit.expand,
          children: [
            _videoContent(item, active),
            if (seeking)
              Center(
                child: IgnorePointer(
                  child: Text(
                    '${DurationUtils.formatDuration(_seekSeconds!.toInt())} / ${DurationUtils.formatDuration(widget.playerController.duration.value)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: seeking
            ? const SizedBox.shrink()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _action(
                    Icons.thumb_up,
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
                      FontAwesomeIcons.solidCommentDots,
                      NumUtils.numFormat(stat?.reply),
                      ready ? _openComments : null,
                      semantics: '评论',
                    ),
                  _action(
                    FontAwesomeIcons.b,
                    NumUtils.numFormat(stat?.coin),
                    ready ? intro.actionCoinVideo : null,
                    color: ready && intro.coinNum.value > 0
                        ? AppDesign.like
                        : Colors.white,
                    semantics: '投币',
                  ),
                  _action(
                    Icons.star_rounded,
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
                    FontAwesomeIcons.share,
                    NumUtils.numFormat(stat?.share),
                    ready ? () => intro.actionShareVideo(context) : null,
                    semantics: '分享',
                  ),
                ],
              ),
        information: seeking
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                physics: active && _titleExpanded
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (labels.isNotEmpty) ...[
                      FeedContentTags(labels: labels),
                      const SizedBox(height: 5),
                    ],
                    Row(
                      children: [
                        InkWell(
                          onTap: ready
                              ? () => Get.toNamed('/member?mid=${owner.mid}')
                              : null,
                          child: NetworkImgLayer(
                            src: face,
                            type: .avatar,
                            width: 40,
                            height: 40,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: InkWell(
                            onTap: ready
                                ? () => Get.toNamed('/member?mid=${owner.mid}')
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  owner.name ?? 'UP主',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: followed
                                        ? Colors.white
                                        : const Color(0xFFFB7299),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (followers != null)
                                  Text(
                                    '${NumUtils.numFormat(followers)}粉丝',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (!self) ...[
                          const SizedBox(width: 6),
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
                    const SizedBox(height: 6),
                    if (detail?.hasSeason == true)
                      Text(
                        '合集 · ${detail!.ugcSeason!.title ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    GestureDetector(
                      onTap: active
                          ? () =>
                                setState(() => _titleExpanded = !_titleExpanded)
                          : null,
                      child: Text(
                        title,
                        maxLines: active && _titleExpanded ? null : 2,
                        overflow: active && _titleExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${NumUtils.numFormat(stat?.view ?? item.stat.view)}播放',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (_author == null &&
                            widget.authorLoader != null &&
                            owner.mid != null)
                          TextButton.icon(
                            onPressed: ready
                                ? () => _openAuthorFeed(
                                    Owner(
                                      mid: owner.mid,
                                      name: owner.name,
                                      face: face,
                                    ),
                                  )
                                : null,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(
                              Icons.video_library_outlined,
                              size: 13,
                            ),
                            label: const Text(
                              'UP主视频',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
        footer: Column(
          children: [
            _progress(item, active, saved?.duration, saved?.position),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: active && !_switching
                            ? () => Get.find<VideoDetailController>(
                                tag: intro.heroTag,
                              ).showShootDanmakuSheet()
                            : null,
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.only(left: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF27252B),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '发个友善的弹幕见证当下',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    widget
                                        .playerController
                                        .enableShowDanmaku
                                        .value
                                    ? '关闭弹幕'
                                    : '打开弹幕',
                                onPressed: active
                                    ? () {
                                        setState(() {
                                          widget
                                              .playerController
                                              .enableShowDanmaku
                                              .value = !widget
                                              .playerController
                                              .enableShowDanmaku
                                              .value;
                                        });
                                      }
                                    : null,
                                icon: Icon(
                                  Icons.subtitles_outlined,
                                  color:
                                      widget
                                          .playerController
                                          .enableShowDanmaku
                                          .value
                                      ? Colors.white
                                      : Colors.white38,
                                  size: 21,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _topButton('视频详情', Icons.crop_free, widget.onDetails),
                    _topButton(
                      '全屏观看',
                      Icons.screen_rotation_outlined,
                      _toggleCinema,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  });

  Widget _progress(
    StoryVideoItem item,
    bool active,
    int? oldDuration,
    int? oldPosition,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: FeedProgressRegion(
      active: active,
      height: 32,
      builder: (context) {
        final controller = widget.playerController;
        final total = active
            ? controller.duration.value
            : oldDuration ?? item.duration;
        final position = active ? controller.progress : oldPosition ?? 0;
        return ProgressBar(
          progress: position.clamp(0, total > 0 ? total : 0),
          buffered: active ? controller.buffered.value : 0,
          total: total > 0 ? total : 0,
          progressBarColor: Colors.white,
          baseBarColor: Colors.white24,
          bufferedBarColor: Colors.white38,
          thumbColor: Colors.white,
          thumbGlowColor: Colors.white24,
          barHeight: _seekSeconds == null ? 1.3 : 3.5,
          thumbRadius: _seekSeconds == null ? 2 : 7,
          thumbGlowRadius: 25,
          onDragStart: active && total > 0
              ? (details) {
                  feedBack();
                  controller.onSeekStart(details.seconds);
                  setState(() => _seekSeconds = details.seconds.toDouble());
                }
              : null,
          onDragUpdate: active && total > 0
              ? (details) {
                  if (!controller.isFileSource && controller.showSeekPreview)
                    controller.updatePreviewIndex(details.seconds);
                  controller.seekPosition.value = details.seconds;
                  setState(() => _seekSeconds = details.seconds.toDouble());
                }
              : null,
          onDragEnd: active
              ? () {
                  controller.onSeekEnd();
                  if (mounted) setState(() => _seekSeconds = null);
                }
              : null,
          onSeek: active && total > 0
              ? (ms) {
                  controller
                    ..position.value = ms ~/ 1000
                    ..onSeekEnd()
                    ..seekTo(Duration(milliseconds: ms), isSeek: false);
                  if (mounted) setState(() => _seekSeconds = null);
                }
              : null,
        );
      },
    ),
  );

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

import 'package:PiliPlus/common/design_tokens.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showFeedMore(
  BuildContext context, {
  required PlPlayerController player,
  required VideoDetailController detail,
  required UgcIntroController intro,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppDesign.playerSheet,
  shape: const RoundedRectangleBorder(borderRadius: AppDesign.sheetRadius),
  builder: (sheetContext) => Theme(
    data: ThemeUtils.darkTheme.copyWith(
      colorScheme: ThemeUtils.darkTheme.colorScheme.copyWith(
        surface: AppDesign.playerSheet,
        surfaceContainerLowest: AppDesign.playerSheet,
        primary: AppDesign.playerPrimary,
      ),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      '更多操作',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  const Text(
                    '播放速度',
                    style: TextStyle(
                      color: AppDesign.playerMuted,
                      fontSize: 12,
                    ),
                  ),
                  StatefulBuilder(
                    builder: (context, setState) => Wrap(
                      spacing: 8,
                      children: [
                        for (final speed in player.speedList)
                          ChoiceChip(
                            label: Text('$speed×'),
                            selected: player.playbackSpeed == speed,
                            onSelected: (_) async {
                              await player.setPlaybackSpeed(speed);
                              if (context.mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '画面',
                    style: TextStyle(
                      color: AppDesign.playerMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () => SegmentedButton<VideoFitType>(
                      segments: const [
                        ButtonSegment(
                          value: VideoFitType.contain,
                          label: Text('适应'),
                          icon: Icon(Icons.fit_screen),
                        ),
                        ButtonSegment(
                          value: VideoFitType.cover,
                          label: Text('填充'),
                          icon: Icon(Icons.crop),
                        ),
                      ],
                      selected: {player.videoFit.value},
                      onSelectionChanged: (value) =>
                          player.videoFit.value = value.first,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _entry(
                    context,
                    Icons.high_quality_outlined,
                    '画质',
                    () =>
                        (detail.headerCtrKey.currentState
                                as HeaderControlState?)
                            ?.showSetVideoQa(),
                  ),
                  _entry(
                    context,
                    Icons.closed_caption_outlined,
                    '字幕设置',
                    () =>
                        (detail.headerCtrKey.currentState
                                as HeaderControlState?)
                            ?.showSetSubtitle(),
                  ),
                  _entry(
                    context,
                    Icons.subtitles_outlined,
                    '弹幕设置',
                    () =>
                        (detail.headerCtrKey.currentState
                                as HeaderControlState?)
                            ?.showSetDanmaku(),
                  ),
                  _entry(
                    context,
                    Icons.watch_later_outlined,
                    intro.hasLater.value ? '移出稍后再看' : '稍后再看',
                    () => intro.handleAction(intro.viewLater),
                  ),
                  _entry(
                    context,
                    Icons.toll_outlined,
                    '投币',
                    () => intro.handleAction(intro.actionCoinVideo),
                  ),
                  _entry(
                    context,
                    Icons.star_outline_rounded,
                    '选择收藏夹',
                    () => intro.handleAction(intro.actionFavVideo),
                  ),
                  _entry(
                    context,
                    Icons.download_outlined,
                    '离线缓存',
                    () => detail.onDownload(context),
                  ),
                  _entry(
                    context,
                    Icons.link,
                    '复制视频链接',
                    () => Utils.copyText(
                      'https://www.bilibili.com/video/${intro.bvid}',
                    ),
                  ),
                  _entry(
                    context,
                    Icons.flag_outlined,
                    '举报',
                    () => PageUtils.reportVideo(detail.aid),
                  ),
                  _entry(
                    context,
                    Icons.settings_outlined,
                    '更多播放器设置',
                    () =>
                        (detail.headerCtrKey.currentState
                                as HeaderControlState?)
                            ?.showSettingSheet(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _entry(
  BuildContext context,
  IconData icon,
  String title,
  VoidCallback onTap,
) => ListTile(
  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
  minTileHeight: 56,
  leading: Icon(icon, size: 22),
  title: Text(title),
  trailing: const Icon(Icons.chevron_right, size: 20),
  onTap: () {
    Navigator.pop(context);
    onTap();
  },
);

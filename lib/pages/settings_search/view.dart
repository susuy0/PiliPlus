import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/pages/search/controller.dart' show DebounceStreamState;
import 'package:PiliPlus/pages/setting/models/extra_settings.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/models/privacy_settings.dart';
import 'package:PiliPlus/pages/setting/models/recommend_settings.dart';
import 'package:PiliPlus/pages/setting/models/style_settings.dart';
import 'package:PiliPlus/pages/setting/models/video_settings.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState
    extends DebounceStreamState<SettingsSearchPage, String> {
  final _textEditingController = TextEditingController();
  final _list = <(SettingsModel, String)>[].obs;
  final _query = ''.obs;
  late final _settings = <(SettingsModel, String)>[
    for (final item in privacySettings) (item, '账号与隐私 / 隐私设置'),
    for (final item in recommendSettings) (item, '推荐与内容 / 推荐流设置'),
    for (final item in videoSettings) (item, '播放器与竖屏 / 音视频设置'),
    for (final item in playSettings) (item, '播放器与竖屏 / 播放器设置'),
    for (final item in styleSettings) (item, '外观与布局 / 外观设置'),
    for (final item in extraSettings) (item, '系统与工具 / 其它设置'),
  ];

  @override
  void onValueChanged(String value) {
    _query.value = value;
    if (value.isEmpty) {
      _list.clear();
    } else {
      value = value.toLowerCase();
      _list.value = _settings
          .where(
            (item) =>
                item.$1.effectiveTitle.toLowerCase().contains(value) ||
                item.$1.effectiveSubtitle?.toLowerCase().contains(value) ==
                    true ||
                item.$2.contains(value),
          )
          .toList();
    }
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () {
              if (_textEditingController.text.isNotEmpty) {
                _textEditingController.clear();
                onValueChanged('');
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.clear),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          controller: _textEditingController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: ctr!.add,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '搜索设置',
            visualDensity: .standard,
            border: InputBorder.none,
          ),
        ),
      ),
      body: ViewInsetsSafeArea(
        child: CustomScrollView(
          slivers: [
            ViewSliverSafeArea(
              sliver: Obx(
                () => _list.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.manage_search,
                                size: 48,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _query.isEmpty ? '查找你需要的设置' : '没有找到相关设置',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _query.isEmpty ? '试试「竖屏」「画质」「主题」' : '试试更短的关键词',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      )
                    : SliverMasonryGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      0,
                                    ),
                                    child: Text(
                                      _list[index].$2,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                    ),
                                  ),
                                  _list[index].$1.widget,
                                ],
                              ),
                            ),
                          ),
                          childCount: _list.length,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final gridDelegate = SliverSimpleGridDelegateWithMaxCrossAxisExtent_(
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
  );
}

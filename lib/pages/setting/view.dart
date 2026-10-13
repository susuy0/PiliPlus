import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/about/view.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class _SettingsModel {
  final SettingType type;
  final String? subtitle;
  final Icon icon;

  const _SettingsModel({
    required this.type,
    this.subtitle,
    required this.icon,
  });
}

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late SettingType _type = SettingType.privacySetting;
  final RxBool _noAccount = Accounts.account.isEmpty.obs;
  late bool _isPortrait;
  late ThemeData theme;

  static const List<_SettingsModel> _items = [
    _SettingsModel(
      type: SettingType.privacySetting,
      subtitle: '黑名单',
      icon: Icon(Icons.privacy_tip_outlined),
    ),
    _SettingsModel(
      type: SettingType.recommendSetting,
      subtitle: '推荐来源（web/app）、刷新保留内容、过滤器',
      icon: Icon(Icons.explore_outlined),
    ),
    _SettingsModel(
      type: SettingType.videoSetting,
      subtitle: '画质、音质、解码、缓冲、音频输出等',
      icon: Icon(Icons.video_settings_outlined),
    ),
    _SettingsModel(
      type: SettingType.playSetting,
      subtitle: '双击/长按、全屏、后台播放、弹幕、字幕、底部进度条等',
      icon: Icon(Icons.touch_app_outlined),
    ),
    _SettingsModel(
      type: SettingType.styleSetting,
      subtitle: '横屏适配（平板）、侧栏、列宽、首页、动态红点、主题、字号、图片、帧率等',
      icon: Icon(Icons.style_outlined),
    ),
    _SettingsModel(
      type: SettingType.extraSetting,
      subtitle: '震动、搜索、收藏、ai、评论、动态、代理、更新检查等',
      icon: Icon(Icons.extension_outlined),
    ),
    _SettingsModel(
      type: SettingType.webdavSetting,
      icon: Icon(MdiIcons.databaseCogOutline),
    ),
    _SettingsModel(
      type: SettingType.about,
      icon: Icon(Icons.info_outline),
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    theme = Theme.of(context);
    _isPortrait = MediaQuery.sizeOf(context).isPortrait;
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        title: _isPortrait ? const Text('设置') : Text(_type.title),
      ),
      body: ViewSafeArea(
        child: _isPortrait
            ? _buildList(theme)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildList(theme),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                  Expanded(
                    flex: 6,
                    child: switch (_type) {
                      .privacySetting ||
                      .recommendSetting ||
                      .videoSetting ||
                      .playSetting ||
                      .styleSetting ||
                      .extraSetting => CommonSetting(
                        settingType: _type,
                        showAppBar: false,
                      ),
                      .webdavSetting => const WebDavSettingPage(
                        showAppBar: false,
                      ),
                      .about => const AboutPage(showAppBar: false),
                    },
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _noAccount.close();
    super.dispose();
  }

  void _toPage(SettingType type) {
    if (_isPortrait) {
      Get.to(
        () => switch (type) {
          .privacySetting ||
          .recommendSetting ||
          .videoSetting ||
          .playSetting ||
          .styleSetting ||
          .extraSetting => CommonSetting(settingType: type),
          .webdavSetting => const WebDavSettingPage(),
          .about => const AboutPage(),
        },
      );
    } else {
      _type = type;
      setState(() {});
    }
  }

  Color? _getTileColor(ThemeData theme, SettingType type) {
    if (_isPortrait) {
      return null;
    } else {
      return type == _type ? theme.colorScheme.onInverseSurface : null;
    }
  }

  Widget _buildList(ThemeData theme) {
    final scheme = theme.colorScheme;
    Widget tile(_SettingsModel item) => ListTile(
      tileColor: _getTileColor(theme, item.type),
      onTap: () => _toPage(item.type),
      leading: item.icon,
      title: Text(item.type.title, style: theme.textTheme.titleSmall),
      subtitle: item.subtitle == null
          ? null
          : Text(
              item.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      trailing: Icon(Icons.chevron_right, size: 20, color: scheme.outline),
    );
    Widget group(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 40,
      ),
      children: [
        _buildSearchItem(theme),
        group('账号与隐私', [
          ListTile(
            onTap: () => LoginPageController.switchAccountDialog(context),
            leading: const Icon(Icons.switch_account_outlined),
            title: const Text('切换账号'),
            trailing: const Icon(Icons.chevron_right, size: 20),
          ),
          tile(_items[0]),
          Obx(
            () => _noAccount.value
                ? const SizedBox.shrink()
                : ListTile(
                    leading: Icon(Icons.logout_outlined, color: scheme.error),
                    onTap: () => _logoutDialog(context),
                    title: const Text('退出登录'),
                  ),
          ),
        ]),
        group('推荐与内容', [tile(_items[1])]),
        group('播放器与竖屏', [tile(_items[2]), tile(_items[3])]),
        group('外观与布局', [tile(_items[4])]),
        group('系统与工具', [tile(_items[5]), tile(_items[6]), tile(_items[7])]),
      ],
    );
  }

  Future<void> _removeAccounts(Set<LoginAccount> accounts) async {
    await Accounts.deleteAll(accounts);
    if (mounted) _noAccount.value = Accounts.account.isEmpty;
  }

  static Future<LoginAccount?> _logoutWrapper(LoginAccount account) async {
    try {
      final res = await LoginHttp.logout(account);
      return res.isSuccess ? account : null;
    } catch (e, s) {
      Utils.reportError(e, s);
      return null;
    }
  }

  Future<void> _logoutDialog(BuildContext context) async {
    final result = await showDialog<Set<LoginAccount>>(
      context: context,
      builder: (context) => MultiSelectDialog<LoginAccount>(
        title: '选择要登出的账号uid',
        initValues: const Iterable.empty(),
        values: {
          for (final i in Accounts.account.values) i: i.mid.toString(),
        },
      ),
    );
    if (!context.mounted || result == null || result.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('提示'),
          content: Text(
            "确认要退出以下账号登录吗\n\n${result.map((i) => i.mid).join('\n')}",
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '点错了',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                _removeAccounts(result);
              },
              child: Text(
                '仅登出',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () async {
                SmartDialog.showLoading();
                final res = await Future.wait(result.map(_logoutWrapper));
                SmartDialog.dismiss();
                final logoutAccounts = res.nonNulls.toSet();
                if (logoutAccounts.isEmpty) {
                  SmartDialog.showToast('所选账号均退出登录失败');
                } else {
                  Get.back();
                  _removeAccounts(logoutAccounts);
                  if (logoutAccounts.length != result.length) {
                    result.removeWhere(logoutAccounts.contains);
                    SmartDialog.showToast(
                      '账号 ${result.map((i) => i.mid).join(",")} 退出登录失败',
                    );
                  }
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchItem(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => Get.toNamed('/settingsSearch'),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '搜索设置，例如画质、竖屏、主题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/design_tokens.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoThemeData;
import 'package:flutter/foundation.dart' show PlatformDispatcher;
import 'package:material_ui/material_ui.dart';

abstract final class ThemeUtils {
  static late ThemeData lightTheme;

  static late ThemeData darkTheme;

  static late ThemeMode themeMode;

  static ThemeData get theme {
    if (themeMode == .dark ||
        (themeMode == .system &&
            PlatformDispatcher.instance.platformBrightness == .dark)) {
      return darkTheme;
    }
    return lightTheme;
  }

  static bool get isDarkMode => theme.isDark;

  static String themeUrl(bool isDark) =>
      'native.theme=${isDark ? 2 : 1}&night=${isDark ? 1 : 0}';

  static ThemeData getThemeData({
    required ColorScheme colorScheme,
    required bool isDynamic,
    bool isDark = false,
  }) {
    final fontWeight = Pref.appFontWeight;
    final fontFamily = FontUtils.fontFamily;

    colorScheme = AppDesign.scheme(
      colorScheme,
      defaultAccent: !isDynamic && Pref.customColor == 0,
      pureBlack: isDark && Pref.isPureBlackTheme,
    );
    TextStyle text(
      double size,
      double height, [
      FontWeight weight = FontWeight.w400,
    ]) => TextStyle(
      fontSize: size,
      height: height / size,
      fontWeight: fontWeight == FontWeight.normal ? weight : fontWeight,
    );
    final textTheme = TextTheme(
      titleLarge: text(18, 26, FontWeight.w600),
      titleMedium: text(16, 24, FontWeight.w600),
      titleSmall: text(15, 22, FontWeight.w600),
      bodyLarge: text(15, 24),
      bodyMedium: text(14, 22),
      bodySmall: text(13, 20),
      labelLarge: text(14, 20, FontWeight.w500),
      labelMedium: text(12, 16, FontWeight.w500),
      labelSmall: text(11, 14, FontWeight.w500),
    );

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
          color: colorScheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text(12, 16, FontWeight.w500)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        minWidth: 80,
        indicatorColor: colorScheme.primaryContainer,
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: text(15, 22, FontWeight.w600),
        unselectedLabelStyle: text(15, 22, FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: colorScheme.primary, width: 3),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 20,
        actionTextColor: colorScheme.primary,
        closeIconColor: colorScheme.secondary,
        backgroundColor: colorScheme.secondaryContainer,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: fontWeight,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        surfaceTintColor: isDark ? colorScheme.surfaceContainerHighest : null,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(borderRadius: AppDesign.radius),
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: isDark
          ? ProgressIndicatorThemeData(
              // ignore: deprecated_member_use
              year2023: false,
              refreshBackgroundColor: colorScheme.onInverseSurface,
            )
          // ignore: deprecated_member_use
          : const ProgressIndicatorThemeData(year2023: false),
      dialogTheme: DialogThemeData(
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: fontWeight,
          fontFamily: fontFamily,
          color: colorScheme.onSurface,
        ),
        backgroundColor: colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: Style.bottomSheetRadius,
        ),
      ),
      // ignore: deprecated_member_use
      sliderTheme: const SliderThemeData(year2023: false),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          fontSize: 14,
          color: Colors.white,
          fontFamily: fontFamily,
          fontWeight: fontWeight,
        ),
        decoration: const BoxDecoration(
          color: Color(0xE6616161), // Colors.grey[700]!.withValues(alpha: 0.9)
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        selectionHandleColor: colorScheme.primary,
      ),
      switchTheme: const SwitchThemeData(
        padding: .zero,
        materialTapTargetSize: .shrinkWrap,
        thumbIcon: WidgetStateProperty<Icon?>.fromMap(
          <WidgetStatesConstraint, Icon?>{
            WidgetState.selected: Icon(Icons.done),
            WidgetState.any: null,
          },
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      listTileTheme: ListTileThemeData(
        controlAffinity: .leading,
        minTileHeight: 56,
        iconColor: colorScheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
    return theme;
  }

  static ThemeData darkenTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final color = colorScheme.surfaceContainerHighest.darken(0.7);
    return theme.copyWith(
      canvasColor: Colors.black,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: colorScheme.surfaceContainer.darken(0.75),
      ),
      dialogTheme: theme.dialogTheme.copyWith(backgroundColor: color),
      bottomSheetTheme: theme.bottomSheetTheme.copyWith(
        backgroundColor: color,
      ),
      bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
        backgroundColor: color,
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        backgroundColor: color,
      ),
      navigationRailTheme: theme.navigationRailTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(color: color),
      colorScheme: colorScheme.copyWith(
        primary: colorScheme.primary.darken(0.1),
        onPrimary: colorScheme.onPrimary.darken(0.1),
        primaryContainer: colorScheme.primaryContainer.darken(0.1),
        onPrimaryContainer: colorScheme.onPrimaryContainer.darken(0.1),
        inversePrimary: colorScheme.inversePrimary.darken(0.1),
        secondary: colorScheme.secondary.darken(0.05),
        onSecondary: colorScheme.onSecondary.darken(0.05),
        secondaryContainer: colorScheme.secondaryContainer.darken(0.05),
        onSecondaryContainer: colorScheme.onSecondaryContainer.darken(0.05),
        error: colorScheme.error.darken(0.05),
        surface: Colors.black,
        onSurface: colorScheme.onSurface.darken(0.15),
        surfaceTint: colorScheme.surfaceTint.darken(),
        inverseSurface: colorScheme.inverseSurface.darken(),
        onInverseSurface: colorScheme.onInverseSurface.darken(),
        surfaceContainer: colorScheme.surfaceContainer.darken(),
        surfaceContainerHigh: colorScheme.surfaceContainerHigh.darken(),
        surfaceContainerHighest: colorScheme.surfaceContainerHighest.darken(
          0.4,
        ),
      ),
    );
  }
}

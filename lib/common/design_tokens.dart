import 'package:material_ui/material_ui.dart';

/// Claude's UI kit, shared by native pages. User-selected accent colors still
/// work; neutral surfaces and playback colors remain consistent.
abstract final class AppDesign {
  static const radius = BorderRadius.all(Radius.circular(12));
  static const sheetRadius = BorderRadius.vertical(top: Radius.circular(20));
  static const playerBackground = Color(0xFF000000);
  static const playerSheet = Color(0xFF1B1B1F);
  static const playerContainer = Color(0xFF26262B);
  static const playerMuted = Color(0xFFC9C9D1);
  static const playerPrimary = Color(0xFFFF8DB0);
  static const like = Color(0xFFFF5C8A);
  static const favorite = Color(0xFFFFC83D);

  static ColorScheme scheme(
    ColorScheme source, {
    bool defaultAccent = false,
    bool pureBlack = false,
  }) {
    final dark = source.brightness == Brightness.dark;
    final scheme = source.copyWith(
      surface: Color(
        pureBlack
            ? 0xFF000000
            : dark
            ? 0xFF0E0E10
            : 0xFFF6F6F8,
      ),
      surfaceContainerLowest: Color(
        pureBlack
            ? 0xFF0B0B0C
            : dark
            ? 0xFF17171A
            : 0xFFFFFFFF,
      ),
      surfaceContainerLow: Color(
        pureBlack
            ? 0xFF0B0B0C
            : dark
            ? 0xFF17171A
            : 0xFFFFFFFF,
      ),
      surfaceContainer: Color(
        pureBlack
            ? 0xFF161618
            : dark
            ? 0xFF212125
            : 0xFFEFEFF3,
      ),
      surfaceContainerHigh: Color(
        pureBlack
            ? 0xFF161618
            : dark
            ? 0xFF212125
            : 0xFFEFEFF3,
      ),
      surfaceContainerHighest: Color(
        pureBlack
            ? 0xFF222226
            : dark
            ? 0xFF2C2C32
            : 0xFFE4E4EA,
      ),
      onSurface: Color(dark ? 0xFFF1F1F4 : 0xFF16161A),
      onSurfaceVariant: Color(dark ? 0xFFBDBDC7 : 0xFF4B4B55),
      outline: Color(dark ? 0xFF8E8E99 : 0xFF80808B),
      outlineVariant: Color(
        pureBlack
            ? 0xFF232327
            : dark
            ? 0xFF2F2F35
            : 0xFFE3E3E8,
      ),
      error: Color(dark ? 0xFFFF8A80 : 0xFFC62828),
    );
    if (!defaultAccent) return scheme;
    return scheme.copyWith(
      primary: Color(dark ? 0xFFFF8DB0 : 0xFFCC2F63),
      onPrimary: Color(dark ? 0xFF4D0B25 : 0xFFFFFFFF),
      primaryContainer: Color(
        pureBlack
            ? 0xFF4A1028
            : dark
            ? 0xFF5E1633
            : 0xFFFFE0E9,
      ),
      onPrimaryContainer: Color(dark ? 0xFFFFD9E4 : 0xFF5A0A27),
      secondary: Color(dark ? 0xFFFFB3CB : 0xFFA3224F),
      secondaryContainer: Color(dark ? 0xFF5E1633 : 0xFFFFE0E9),
      onSecondaryContainer: Color(dark ? 0xFFFFD9E4 : 0xFF5A0A27),
    );
  }

  static Duration motion(BuildContext context, [int milliseconds = 240]) =>
      Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context)
            ? 0
            : milliseconds,
      );
}

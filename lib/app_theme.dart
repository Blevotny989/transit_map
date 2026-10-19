import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Палитра старинной карты в духе пиратов Карибского моря.
class Pirate {
  static const parchment = Color(0xFFF3E4C0);
  static const parchmentDark = Color(0xFFE6D2A1);
  static const ink = Color(0xFF3A2410);
  static const brown = Color(0xFF5B3A1A);
  static const sea = Color(0xFF2F6F73);
  static const wax = Color(0xFF9C2F1F);
  static const gold = Color(0xFFC9A24B);
}

ThemeData modernTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2979FF), brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
  );
}

ThemeData? _pirate;

ThemeData pirateTheme() => _pirate ??= _buildPirate();

ThemeData _buildPirate() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  final scheme = ColorScheme.fromSeed(seedColor: Pirate.brown, brightness: Brightness.light).copyWith(
    primary: Pirate.brown,
    onPrimary: Pirate.parchment,
    secondary: Pirate.sea,
    onSecondary: Colors.white,
    tertiary: Pirate.wax,
    surface: Pirate.parchment,
    onSurface: Pirate.ink,
    surfaceContainerHighest: Pirate.parchmentDark,
    primaryContainer: Pirate.parchmentDark,
    onPrimaryContainer: Pirate.ink,
    onSurfaceVariant: const Color(0xFF6B4A24),
    outline: Pirate.brown,
    error: Pirate.wax,
  );
  var tt = GoogleFonts.getTextTheme('Kurale', base.textTheme)
      .apply(bodyColor: Pirate.ink, displayColor: Pirate.ink);
  TextStyle? head(TextStyle? s) =>
      GoogleFonts.getFont('Marck Script', textStyle: s?.copyWith(fontWeight: FontWeight.w700));
  tt = tt.copyWith(
    titleLarge: head(tt.titleLarge?.copyWith(fontSize: 26)),
    titleMedium: head(tt.titleMedium?.copyWith(fontSize: 21)),
    titleSmall: head(tt.titleSmall?.copyWith(fontSize: 18)),
    headlineSmall: head(tt.headlineSmall),
  );
  final border = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
    side: const BorderSide(color: Pirate.brown, width: 2),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pirate.parchment,
    textTheme: tt,
    primaryTextTheme: tt,
    iconTheme: const IconThemeData(color: Pirate.brown),
    dividerTheme: DividerThemeData(color: Pirate.brown.withAlpha(90)),
    cardTheme: CardThemeData(
      color: Pirate.parchment,
      elevation: 6,
      shadowColor: Colors.black54,
      shape: border,
    ),
    dialogTheme: DialogThemeData(backgroundColor: Pirate.parchment, shape: border),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Pirate.parchment,
      modalBackgroundColor: Pirate.parchment,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: Pirate.brown, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Pirate.parchmentDark,
      selectedColor: Pirate.gold.withAlpha(140),
      side: const BorderSide(color: Pirate.brown, width: 1.2),
      labelStyle: const TextStyle(color: Pirate.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pirate.brown,
        foregroundColor: Pirate.parchment,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Pirate.gold, width: 1.5),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pirate.brown,
        side: const BorderSide(color: Pirate.brown, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Pirate.wax)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Pirate.wax,
      foregroundColor: Pirate.gold,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Pirate.gold, width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Pirate.brown, textColor: Pirate.ink),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Pirate.wax,
      thumbColor: Pirate.wax,
      inactiveTrackColor: Pirate.parchmentDark,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Pirate.gold : Pirate.brown),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Pirate.wax : Pirate.parchmentDark),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: Pirate.brown, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Pirate.parchment),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Pirate.brown,
      contentTextStyle: TextStyle(color: Pirate.parchment),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Pirate.wax),
  );
}

/// Рукописный шрифт для подписей на старинной карте (цвет задаётся при рисовании).
TextStyle pirateScript() => GoogleFonts.getFont('Marck Script', fontWeight: FontWeight.w700);

import 'package:flutter/material.dart';

/// The app's colour, taken from the logo: indigo through violet, with the
/// spark's teal for anything that counts as an accent.
const Color seed = Color(0xFF5B4BE1);

/// Categorical palette for the charts, in fixed order.
///
/// Both modes are selected rather than flipped, and the order is validated:
/// every adjacent pair clears the colour-vision separation floor. A ninth
/// project does not get a ninth hue, it folds into "Other", which is what
/// [seriesColor] does.
const List<Color> lightSeries = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF4A3AA7),
  Color(0xFFE34948),
];

/// The same hues stepped for a dark surface.
const List<Color> darkSeries = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];

/// Anything past the eighth series, and anything unmapped.
Color otherSeries(Brightness brightness) =>
    brightness == Brightness.dark
    ? const Color(0xFF8A8A85)
    : const Color(0xFF6E6E68);

/// Palette slot [index] for [brightness], folded into the "other" grey once the
/// slots run out.
Color seriesColor(int index, Brightness brightness) {
  final palette = brightness == Brightness.dark ? darkSeries : lightSeries;
  return index < 0 || index >= palette.length
      ? otherSeries(brightness)
      : palette[index];
}

/// Reads `#AARRGGBB`, the shape WorkingHours stores a colour in.
Color? parseArgb(String? value) {
  if (value == null) return null;
  final hex = value.replaceAll('#', '');
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Writes `#AARRGGBB`, the shape WorkingHours stores a colour in.
String formatArgb(Color color) {
  String hex(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${hex(color.a)}${hex(color.r)}${hex(color.g)}${hex(color.b)}'
      .toUpperCase();
}

/// Theme for [brightness], Material 3 with a slightly tighter desktop density.
ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}

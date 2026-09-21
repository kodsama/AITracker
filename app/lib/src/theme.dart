import 'package:flutter/material.dart';

/// The app's colour, taken from the logo: indigo through violet, with the
/// spark's teal for anything that counts as an accent.
const Color seed = Color(0xFF5B4BE1);

/// Accent used for totals and the running MCP endpoint.
const Color spark = Color(0xFF34D399);

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

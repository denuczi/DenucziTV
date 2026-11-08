import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

/// Brand tokens and semantic status colors. Keep errors, success and warnings
/// semantically distinct, rather than making every action red.
abstract final class AppPalette {
  static const brandBlack = Color(0xFF000000);
  static const brandWhite = Color(0xFFFFFFFF);
  static const brandRed = Color(0xFFE60023);
  static const canvas = Color(0xFF080809);
  static const sidebar = Color(0xFF101012);
  static const surface = Color(0xFF161619);
  static const elevated = Color(0xFF202024);
  static const elevatedHover = Color(0xFF2B2B30);
  static const text = Color(0xFFF7F7F8);
  static const muted = Color(0xFFB6B6BF);
  static const lightAccent = brandRed;
  static const coral = Color(0xFFF3646E);
  static const amber = Color(0xFFF3C26B);
  static const success = Color(0xFF48C69B);
  static const outline = Color(0xFF38383D);

  static Color information(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFF79B8FF)
      : const Color(0xFF1D5EA8);

  static LinearGradient sidebarGradient(Brightness brightness) =>
      brightness == Brightness.dark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF180B10), Color(0xFF101012), Color(0xFF09090A)],
          stops: [0.0, 0.38, 1.0],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF2F3), Color(0xFFFBFBFD), Color(0xFFFFFFFF)],
          stops: [0.0, 0.45, 1.0],
        );
}

/// Avoids GTK environment queries and uses contrast-adjusted brand red in
/// both themes. The logo keeps the exact black, white and red artwork.
abstract final class AppTheme {
  static final ThemeData dark = _build(Brightness.dark);
  static final ThemeData light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? const Color(0xFFFF5268) : const Color(0xFFAF0023);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.brandRed,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: isDark ? Colors.black : Colors.white,
          // Keep large, low-emphasis surfaces neutral. Red is reserved for
          // interactive accents instead of tinting every Material 3 container.
          primaryContainer: isDark
              ? const Color(0xFF29272B)
              : const Color(0xFFF0F0F2),
          onPrimaryContainer: isDark
              ? AppPalette.text
              : const Color(0xFF29272B),
          secondary: isDark ? const Color(0xFFBABAC2) : const Color(0xFF62626B),
          onSecondary: isDark ? AppPalette.canvas : Colors.white,
          secondaryContainer: isDark
              ? const Color(0xFF2B2B30)
              : const Color(0xFFEDEDF0),
          onSecondaryContainer: isDark
              ? AppPalette.text
              : const Color(0xFF29272B),
          tertiary: isDark ? AppPalette.amber : const Color(0xFF8C590A),
          onTertiary: isDark ? AppPalette.canvas : Colors.white,
          tertiaryContainer: isDark
              ? const Color(0xFF302C25)
              : const Color(0xFFF2F0EA),
          onTertiaryContainer: isDark
              ? AppPalette.text
              : const Color(0xFF403526),
          surfaceTint: Colors.transparent,
          surface: isDark ? AppPalette.canvas : const Color(0xFFFEFEFF),
          onSurface: isDark ? AppPalette.text : const Color(0xFF161619),
          onSurfaceVariant: isDark ? AppPalette.muted : const Color(0xFF55525A),
          surfaceContainerLowest: isDark ? AppPalette.canvas : Colors.white,
          surfaceContainerLow: isDark
              ? AppPalette.sidebar
              : const Color(0xFFF8F8FA),
          surfaceContainer: isDark
              ? AppPalette.surface
              : const Color(0xFFF3F3F6),
          surfaceContainerHigh: isDark
              ? AppPalette.elevated
              : const Color(0xFFEDECF0),
          surfaceContainerHighest: isDark
              ? AppPalette.elevatedHover
              : const Color(0xFFE6E4E9),
          outline: isDark ? AppPalette.outline : const Color(0xFF9C97A1),
          outlineVariant: isDark
              ? const Color(0xFF323236)
              : const Color(0xFFD6D1D8),
        );
    final yaru = createYaruTheme(colorScheme: scheme);
    return yaru.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      // Selected tabs and chips must be legible without a pink fill.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLow,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.surfaceContainerHigh,
        checkmarkColor: scheme.primary,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
    );
  }
}

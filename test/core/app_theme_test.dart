import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';

void main() {
  test('dark mode uses the established graphite brand surfaces', () {
    final scheme = AppTheme.dark.colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface, AppPalette.canvas);
    expect(scheme.surfaceContainerLow, AppPalette.sidebar);
    expect(scheme.surfaceContainer, AppPalette.surface);
    expect(scheme.surfaceContainerHigh, AppPalette.elevated);
    expect(scheme.primary, isNot(scheme.error));
  });

  test('selected surfaces remain neutral in both themes', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final scheme = theme.colorScheme;
      final selectedTab = theme.segmentedButtonTheme.style!.backgroundColor!
          .resolve({WidgetState.selected});
      expect(selectedTab, scheme.surfaceContainerHigh);
      expect(theme.chipTheme.selectedColor, scheme.surfaceContainerHigh);
      expect(scheme.surfaceTint, Colors.transparent);
    }

    expect(
      AppTheme.light.colorScheme.primaryContainer,
      const Color(0xFFF0F0F2),
    );
    expect(AppTheme.dark.colorScheme.primaryContainer, const Color(0xFF29272B));
  });

  test('text and interactive elements meet minimum contrast', () {
    double ratio(Color one, Color two) {
      final first = one.computeLuminance();
      final second = two.computeLuminance();
      final higher = first > second ? first : second;
      final lower = first > second ? second : first;
      return (higher + 0.05) / (lower + 0.05);
    }

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final scheme = theme.colorScheme;
      expect(ratio(scheme.onSurface, scheme.surface), greaterThan(7));
      expect(
        ratio(scheme.onSurface, scheme.surfaceContainerHigh),
        greaterThan(7),
      );
      expect(ratio(scheme.onPrimary, scheme.primary), greaterThan(4.5));
    }
  });

  test('light mode uses neutral surfaces and a distinct semantic error', () {
    final scheme = AppTheme.light.colorScheme;
    expect(scheme.brightness, Brightness.light);
    expect(scheme.surface, const Color(0xFFFEFEFF));
    expect(scheme.surfaceContainerLow, const Color(0xFFF8F8FA));
    expect(scheme.surfaceContainer, const Color(0xFFF3F3F6));
    expect(scheme.primary, isNot(scheme.error));
  });
}

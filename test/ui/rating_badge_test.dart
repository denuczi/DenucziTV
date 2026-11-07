import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/presentation/rating_badge.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('rating badge is distinct in ${mode.name} mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: const Scaffold(
            body: Center(child: RatingBadge(rating: '8.5')),
          ),
        ),
      );
      expect(find.text('Rating 8.5'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      final label = tester.widget<Text>(find.text('Rating 8.5'));
      expect(label.style?.color, isNotNull);
    });
  }
  testWidgets('long provider ratings are shortened in the badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: RatingBadge(rating: '6.307')),
        ),
      ),
    );
    expect(find.text('Rating 6.3'), findsOneWidget);
    expect(find.text('Rating 6.307'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/shared/widgets/empty_state.dart';

void main() {
  testWidgets('empty states include a readable title and action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.info_outline,
            title: 'No results',
            description: 'Try another search.',
            action: Text('Retry'),
          ),
        ),
      ),
    );
    expect(find.text('No results'), findsOneWidget);
    expect(find.text('Try another search.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

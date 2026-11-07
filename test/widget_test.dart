import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/shared/widgets/empty_state.dart';

void main() {
  testWidgets('the empty library view is accessible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.video_library_outlined,
            title: 'Media library',
            description: 'Connect a provider to get started.',
          ),
        ),
      ),
    );
    expect(find.text('Media library'), findsOneWidget);
    expect(find.text('Connect a provider to get started.'), findsOneWidget);
  });
}

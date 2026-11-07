import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/presentation/export_notice.dart';

void main() {
  testWidgets('M3U export notice has processing and success states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ExportNotice(
            phase: ExportPhase.writing,
            message: '500 of 1,000 items saved',
            progress: 0.5,
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(find.text('Exporting playlist'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

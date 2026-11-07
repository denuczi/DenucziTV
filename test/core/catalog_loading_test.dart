import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/presentation/catalog_loading.dart';

void main() {
  testWidgets('loading status is centered in the remaining area', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: CatalogLoading())),
      ),
    );
    final progress = find.byType(CircularProgressIndicator);
    expect(progress, findsOneWidget);
    expect(find.text('Loading your library'), findsOneWidget);
    expect(find.text('No results'), findsNothing);
    final viewport = tester.getRect(find.byType(Scaffold));
    final position = tester.getCenter(progress);
    expect((position.dx - viewport.center.dx).abs(), lessThan(1));
    expect((position.dy - viewport.center.dy).abs(), lessThan(120));
  });
}

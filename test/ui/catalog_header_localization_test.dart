import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/catalog_header.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';

void main() {
  testWidgets('header stays horizontally centered with actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: CatalogHeader(
              kind: LibraryKind.live,
              total: 12581,
              visible: 12581,
              loading: false,
              exportAvailable: true,
              exporting: false,
              onExport: () {},
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.text('TV en vivo');
    expect(title, findsOneWidget);
    expect(find.text('12.581 canales'), findsOneWidget);
    final center = tester.getCenter(find.byType(CatalogHeader)).dx;
    expect((tester.getCenter(title).dx - center).abs(), lessThan(1.0));
  });

  testWidgets('pluralization uses Spanish neutral nouns', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(
          body: CatalogHeader(
            kind: LibraryKind.movies,
            total: 1,
            visible: 1,
            loading: false,
            exportAvailable: false,
            exporting: false,
            onRefresh: _noop,
            onExport: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 película'), findsOneWidget);
  });
}

void _noop() {}

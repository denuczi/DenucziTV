import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:denuczi_tv/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/presentation/season_selector.dart';

void main() {
  testWidgets(
    'all seasons remain reachable from desktop navigation and picker',
    (tester) async {
      tester.view.physicalSize = const Size(640, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selected = 1;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 550,
                height: 44,
                child: StatefulBuilder(
                  builder: (context, setDialogState) => SeasonSelector(
                    seasons: List.generate(8, (index) => index + 1),
                    selectedSeason: selected,
                    episodeCountForSeason: (_) => 23,
                    onSelected: (season) =>
                        setDialogState(() => selected = season),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nextSeasonChips')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('nextSeasonChips')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('nextSeasonChips')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('browseAllSeasons')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a season'), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().seasonsAvailable(8)),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('seasonPicker-8')),
        120,
        scrollable: find.descendant(
          of: find.byKey(const Key('allSeasonsList')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const Key('seasonPicker-8')));
      await tester.pumpAndSettle();
      expect(selected, 8);
      expect(find.text('Choose a season'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

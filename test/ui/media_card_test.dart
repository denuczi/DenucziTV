import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/media_card.dart';

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'poster hover stays red and white in ${theme.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(600, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final network = NetworkClient();
        addTearDown(network.dispose);
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 190,
                  height: 295,
                  child: MediaCard(
                    entry: const MediaEntry(
                      id: '1',
                      title: 'Long movie title with a subtitle',
                      kind: LibraryKind.movies,
                    ),
                    network: network,
                    onOpen: () => opened++,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Long movie title with a subtitle'), findsOneWidget);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        await mouse.moveTo(
          tester.getCenter(find.byKey(const Key('mediaCardAction'))),
        );
        await tester.pumpAndSettle();
        final arrow = find.byIcon(Icons.arrow_outward_rounded);
        expect(tester.widget<Icon>(arrow).color, Colors.white);
        final affordance = tester.widget<DecoratedBox>(
          find.ancestor(of: arrow, matching: find.byType(DecoratedBox)).first,
        );
        expect(
          (affordance.decoration as BoxDecoration).color,
          theme.brightness == Brightness.dark
              ? AppPalette.brandRed
              : theme.colorScheme.primary,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('mediaCardAction')));
        expect(opened, 1);
      },
    );

    testWidgets(
      'LIVE badge is red with white text in ${theme.brightness.name}',
      (tester) async {
        final network = NetworkClient();
        addTearDown(network.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SizedBox(
                width: 190,
                height: 295,
                child: MediaCard(
                  entry: const MediaEntry(
                    id: 'live',
                    title: 'Channel',
                    kind: LibraryKind.live,
                  ),
                  network: network,
                  onOpen: () {},
                ),
              ),
            ),
          ),
        );
        final label = find.text('LIVE');
        expect(tester.widget<Text>(label).style!.color, Colors.white);
        final badge = tester.widget<DecoratedBox>(
          find.ancestor(of: label, matching: find.byType(DecoratedBox)).first,
        );
        expect((badge.decoration as BoxDecoration).color, AppPalette.brandRed);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

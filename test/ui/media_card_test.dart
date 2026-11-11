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

    testWidgets('Live TV number notch follows the bottom edge in '
        '${theme.brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(600, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final network = NetworkClient();
      addTearDown(network.dispose);
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
                    id: '42',
                    title: 'HBO',
                    kind: LibraryKind.live,
                    channelNumber: 3000,
                  ),
                  network: network,
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final notch = find.byKey(const Key('liveChannelNumberNotch'));
      expect(notch, findsOneWidget);
      expect(find.text('3.000'), findsOneWidget);
      final numberText = tester.widget<Text>(find.text('3.000'));
      final titleText = tester.widget<Text>(find.text('HBO'));
      expect(
        numberText.style!.fontSize,
        lessThanOrEqualTo(titleText.style!.fontSize!),
      );
      expect(find.text('Live TV'), findsNothing);
      expect(
        (tester.getCenter(notch).dx -
                tester.getCenter(find.byKey(const Key('mediaCardAction'))).dx)
            .abs(),
        lessThan(1),
      );
      // The notch spans the footer instead of appearing as a floating badge.
      expect(tester.getSize(notch).height, 19);
      expect(tester.getSize(notch).width, greaterThan(180));
      expect(find.byKey(const Key('liveChannelNumberPill')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('oversized channel numbers fit without overflowing in '
        '${theme.brightness.name}', (tester) async {
      final network = NetworkClient();
      addTearDown(network.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              width: 142,
              height: 270,
              child: MediaCard(
                entry: const MediaEntry(
                  id: 'max',
                  title: 'Channel',
                  kind: LibraryKind.live,
                  channelNumber: 9223372036854775807,
                ),
                network: network,
                onOpen: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('9.223.372.036.854.775.807'), findsOneWidget);
      expect(find.byKey(const Key('liveChannelNumberNotch')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the inset number remains part of the card tap target in '
        '${theme.brightness.name}', (tester) async {
      final network = NetworkClient();
      addTearDown(network.dispose);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              width: 190,
              height: 295,
              child: MediaCard(
                entry: const MediaEntry(
                  id: '10',
                  title: 'HBO',
                  kind: LibraryKind.live,
                  channelNumber: 10,
                ),
                network: network,
                onOpen: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('liveChannelNumberNotch')));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('movies and series never display channel numbering in '
        '${theme.brightness.name}', (tester) async {
      final network = NetworkClient();
      addTearDown(network.dispose);
      for (final kind in [LibraryKind.movies, LibraryKind.series]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SizedBox(
                width: 190,
                height: 295,
                child: MediaCard(
                  entry: MediaEntry(
                    id: kind.name,
                    title: 'Sample',
                    kind: kind,
                    channelNumber: 17,
                  ),
                  network: network,
                  onOpen: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('liveChannelNumberNotch')), findsNothing);
        expect(find.text('17'), findsNothing);
        expect(find.text(kind.label), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

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

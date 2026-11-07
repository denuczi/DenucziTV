import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/media_card.dart';

void main() {
  testWidgets('poster tile is clickable and remains readable on hover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final network = NetworkClient();
    addTearDown(network.dispose);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
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
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('mediaCardAction')));
    expect(opened, 1);
  });
}

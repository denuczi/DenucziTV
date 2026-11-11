import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/player/presentation/live_channel_indicator.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('typed numbers are legible without showing a channel logo', (
    tester,
  ) async {
    final network = NetworkClient();
    addTearDown(network.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LiveChannelIndicator(
              notice: const LiveChannelNotice.forDigits('152'),
              network: network,
            ),
          ),
        ),
      ),
    );
    expect(find.text('152'), findsOneWidget);
    expect(find.byIcon(Icons.live_tv_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'channel name and fallback logo remain readable on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(450, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final network = NetworkClient();
      addTearDown(network.dispose);
      const channel = MediaEntry(
        id: '1',
        title: 'Extremely long live channel name that must never overflow',
        kind: LibraryKind.live,
        channelNumber: 7,
        imageUrl: 'not-a-valid-logo',
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: LiveChannelIndicator(
                  notice: const LiveChannelNotice.forChannel(channel),
                  network: network,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Channel 7'), findsOneWidget);
      expect(find.byIcon(Icons.live_tv_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

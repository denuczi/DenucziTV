import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/shell/presentation/desktop_shell.dart';
import 'package:denuczi_tv/shared/widgets/workspace_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const _capture = Key('workspaceCapture');

Future<({int width, Uint8List pixels})> _frame(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (width: image.width, pixels: data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

List<int> _pixel(({int width, Uint8List pixels}) frame, int x, int y) {
  final offset = (y * frame.width + x) * 4;
  return frame.pixels.sublist(offset, offset + 4);
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('glow is circular and only appears in dark mode', (tester) async {
    _viewport(tester, const Size(1280, 720));
    Future<void> mount(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: RepaintBoundary(
              key: _capture,
              child: WorkspaceBackground(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(AppTheme.dark);
    final dark = await _frame(tester);
    final center = _pixel(dark, 640, 360);
    // 14% red over the existing canvas: 30% less glow than the original 20%.
    expect(center[0], closeTo(37, 1));
    expect(center[0], greaterThan(center[1] + 24));
    expect(_pixel(dark, 0, 0), [8, 8, 9, 255]);
    // Equal logical distances must have equal tint, even in a wide window.
    final horizontal = _pixel(dark, 840, 360);
    final vertical = _pixel(dark, 640, 560);
    for (var channel = 0; channel < 4; channel++) {
      expect(horizontal[channel], closeTo(vertical[channel], 1));
    }

    await mount(AppTheme.light);
    final light = await _frame(tester);
    for (final point in [const Offset(640, 360), Offset.zero]) {
      expect(_pixel(light, point.dx.toInt(), point.dy.toInt()), [
        254,
        254,
        255,
        255,
      ]);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('header matches the workspace when scrolling and resizing', (
    tester,
  ) async {
    _viewport(tester, const Size(1280, 720));
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final network = NetworkClient();
    final preferences = SharedPreferencesAsync();
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: SettingsStore(preferences),
    );
    addTearDown(controller.dispose);
    controller.activeAccount = const Account(
      id: 'example',
      label: 'Example',
      serverUrl: 'https://provider.example',
      username: 'viewer',
    );
    controller.kind = LibraryKind.movies;
    controller.entries = List.generate(
      100,
      (index) => MediaEntry(
        id: '$index',
        title: 'Example movie $index',
        kind: LibraryKind.movies,
      ),
    );

    var openedCatalog = false;
    Future<void> mount(ThemeData theme) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: MaterialApp(
            theme: theme,
            home: const RepaintBoundary(key: _capture, child: DesktopShell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!openedCatalog) {
        // The app now starts in My Library. Enter the existing catalog before
        // checking its scrolling and header continuity.
        await tester.tap(find.byKey(const Key('navigation-movies')));
        await tester.pumpAndSettle();
        openedCatalog = true;
      }
    }

    Future<void> expectContinuousHeader() async {
      final frame = await _frame(tester);
      final header = tester.getRect(find.byType(WorkspaceHeaderBackground));
      final x = header.left.toInt() + 8;
      final y = header.bottom.round();
      final above = _pixel(frame, x, y - 1);
      final below = _pixel(frame, x, y);
      for (var channel = 0; channel < 4; channel++) {
        expect(above[channel], closeTo(below[channel], 1));
      }
      expect(tester.takeException(), isNull);
    }

    await mount(AppTheme.dark);
    final returnToTop = find.byKey(const Key('returnToTop'));
    expect(
      tester.widget<FloatingActionButton>(returnToTop).backgroundColor,
      AppPalette.brandRed,
    );
    expect(
      tester.widget<FloatingActionButton>(returnToTop).foregroundColor,
      Colors.white,
    );
    final workspace = find.byType(WorkspaceBackground);
    expect(tester.getTopLeft(workspace).dx, 228);
    expect(
      find.descendant(
        of: workspace,
        matching: find.byKey(const Key('navigation-live-tv')),
      ),
      findsNothing,
    );
    await expectContinuousHeader();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(WorkspaceHeaderBackground)).height, 60);
    await expectContinuousHeader();

    tester.view.physicalSize = const Size(780, 600);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(workspace).dx, 68);
    await expectContinuousHeader();

    // Theme changes must not recreate the catalog and discard its scroll state.
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    final offset = scroll.offset;
    await mount(AppTheme.light);
    expect(
      tester.widget<FloatingActionButton>(returnToTop).backgroundColor,
      AppPalette.brandRed,
    );
    expect(
      tester.widget<FloatingActionButton>(returnToTop).foregroundColor,
      Colors.white,
    );
    expect(
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller,
      same(scroll),
    );
    expect(scroll.offset, offset);
    final light = await _frame(tester);
    expect(_pixel(light, 76, 400), [254, 254, 255, 255]);
    expect(tester.takeException(), isNull);
  });
}

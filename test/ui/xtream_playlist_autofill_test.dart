import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/features/connection/presentation/connect_dialog.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openForm(WidgetTester tester, {String language = 'en'}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ConnectDialog()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String field(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

  testWidgets('pasting a get.php link fills manual fields without connecting', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(
      find.byKey(const Key('serverUrl')),
      'http://provider.example:8880/get.php?username=user&password=p%26ss&type=m3u_plus',
    );
    await tester.pump();

    expect(field(tester, 'serverUrl'), 'http://provider.example:8880');
    expect(field(tester, 'username'), 'user');
    expect(field(tester, 'password'), 'p&ss');
    final passwordInput = find.descendant(
      of: find.byKey(const Key('password')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(passwordInput).obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasting an ordinary URL keeps manually entered credentials', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(find.byKey(const Key('username')), 'manual-user');
    await tester.enterText(find.byKey(const Key('password')), 'manual-pass');
    await tester.enterText(
      find.byKey(const Key('serverUrl')),
      'https://provider.example:8443',
    );
    await tester.pump();

    expect(field(tester, 'serverUrl'), 'https://provider.example:8443');
    expect(field(tester, 'username'), 'manual-user');
    expect(field(tester, 'password'), 'manual-pass');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incomplete playlist does not overwrite the manual fields', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(find.byKey(const Key('username')), 'manual-user');
    await tester.enterText(find.byKey(const Key('password')), 'manual-pass');
    const partial = 'https://provider.example/get.php?username=new-user';
    await tester.enterText(find.byKey(const Key('serverUrl')), partial);
    await tester.pump();

    expect(field(tester, 'serverUrl'), partial);
    expect(field(tester, 'username'), 'manual-user');
    expect(field(tester, 'password'), 'manual-pass');
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing a playlist does not truncate the password', (
    tester,
  ) async {
    await openForm(tester);
    const prefix = 'https://provider.example/get.php?username=user&password=';
    await tester.enterText(find.byKey(const Key('serverUrl')), prefix);
    await tester.enterText(find.byKey(const Key('serverUrl')), '${prefix}p');
    await tester.enterText(find.byKey(const Key('serverUrl')), '${prefix}pa');
    await tester.pump();

    expect(field(tester, 'serverUrl'), '${prefix}pa');
    expect(field(tester, 'password'), isEmpty);

    // Confirm the field through the text input action, just as a user would.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(field(tester, 'serverUrl'), 'https://provider.example');
    expect(field(tester, 'username'), 'user');
    expect(field(tester, 'password'), 'pa');
    expect(tester.takeException(), isNull);
  });

  testWidgets('protected link mode never parses a get.php URL', (tester) async {
    await openForm(tester);
    final selector = tester
        .widget<DropdownButtonFormField<AccountConnectionType>>(
          find.byType(DropdownButtonFormField<AccountConnectionType>),
        );
    selector.onChanged!(AccountConnectionType.protectedSingleLink);
    await tester.pumpAndSettle();

    const playlist =
        'https://provider.example/get.php?username=user&password=secret';
    await tester.enterText(find.byKey(const Key('serverUrl')), playlist);
    await tester.pump();
    expect(field(tester, 'serverUrl'), playlist);
    expect(find.byKey(const Key('username')), findsNothing);
    expect(find.byKey(const Key('password')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'es']) {
    testWidgets('explains playlist autofill in $language', (tester) async {
      await openForm(tester, language: language);
      expect(find.textContaining('get.php'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/updates/presentation/release_notes_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only HTTPS browser links are eligible', () {
    for (final blocked in [
      null,
      '',
      'javascript:alert(1)',
      'data:text/html,hi',
      'file:///etc/passwd',
      '/denuczi/DenucziTV',
      'http://github.com/denuczi/DenucziTV',
      'https://user:pass@github.com/denuczi/DenucziTV',
      'https://github.com:444/path',
      'https://example.com/\nhello',
    ]) {
      expect(safeReleaseNotesLink(blocked), isNull, reason: '$blocked');
    }
    expect(
      safeReleaseNotesLink('https://github.com/denuczi/DenucziTV/issues/1')
          ?.host,
      'github.com',
    );
    expect(safeReleaseNotesLink('https://example.com/info')?.scheme, 'https');
  });

  for (final dark in [false, true]) {
    testWidgets(
      'GFM renders with theme colors and without remote images, dark=$dark',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReleaseNotesMarkdown(
                  notes: '''
## Improvements

- **Playback** is more reliable.
- `Live TV` supports channel numbers.

| Type | State |
| --- | --- |
| Live | Ready |

```dart
final sample = 42;
```

![Remote screenshot](https://example.com/screenshot.png)
''',
                  openLink: (_) async => true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
        expect(find.text('Remote screenshot'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('links must pass validation and failed launches are reported', (
    tester,
  ) async {
    final opened = <Uri>[];
    var failures = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReleaseNotesMarkdown(
            notes:
                '[Official](https://github.com/denuczi/DenucziTV) '
                '[Unsafe](javascript:alert(1))',
            openLink: (uri) async {
              opened.add(uri);
              return false;
            },
            onLinkFailure: () => failures++,
          ),
        ),
      ),
    );
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    markdown.onTapLink!('Unsafe', 'javascript:alert(1)', '');
    expect(opened, isEmpty);
    expect(failures, 1);

    markdown.onTapLink!('Official', 'https://github.com/denuczi/DenucziTV', '');
    await tester.pump();
    expect(opened, hasLength(1));
    expect(opened.single.host, 'github.com');
    expect(failures, 2);
  });
}

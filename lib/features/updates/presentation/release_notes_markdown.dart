import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Only user-initiated HTTPS links may leave the release-notes view.
/// Invalid, local, and executable URI schemes are never passed to a launcher.
Uri? safeReleaseNotesLink(String? href) {
  if (href == null || href.isEmpty || href.length > 2048) {
    return null;
  }
  final value = href.trim();
  if (value.isEmpty ||
      value.contains(RegExp(r'[\x00-\x20\x7f\u202a-\u202e\u2066-\u2069]'))) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  return uri;
}

/// Renders GitHub-flavored release notes without loading remote images.
/// Images are represented by their captions to avoid silent network requests
/// or tracking pixels in a modal opened automatically at startup.
class ReleaseNotesMarkdown extends StatelessWidget {
  const ReleaseNotesMarkdown({
    super.key,
    required this.notes,
    required this.openLink,
    this.onLinkFailure,
  });

  final String notes;
  final Future<bool> Function(Uri) openLink;
  final VoidCallback? onLinkFailure;

  Future<void> _follow(Uri uri) async {
    try {
      if (await openLink(uri)) {
        return;
      }
    } catch (_) {
      // A failed external browser launch should not close the update dialog.
    }
    onLinkFailure?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurface,
      height: 1.5,
    );
    return MarkdownBody(
      key: const Key('releaseNotesMarkdown'),
      data: notes,
      selectable: false,
      softLineBreak: true,
      onTapLink: (_, href, _) {
        final uri = safeReleaseNotesLink(href);
        if (uri == null) {
          onLinkFailure?.call();
          return;
        }
        unawaited(_follow(uri));
      },
      // GitHub notes can contain arbitrary image URLs. Never fetch them here.
      imageBuilder: (uri, title, alt) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                color: colors.onSurfaceVariant,
                size: 18,
              ),
              if (alt != null && alt.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    alt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body,
        pPadding: const EdgeInsets.only(bottom: 5),
        h1: theme.textTheme.titleLarge?.copyWith(color: colors.onSurface),
        h2: theme.textTheme.titleMedium?.copyWith(color: colors.onSurface),
        h3: theme.textTheme.titleSmall?.copyWith(color: colors.onSurface),
        h4: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        h1Padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
        h2Padding: const EdgeInsets.fromLTRB(0, 10, 0, 5),
        h3Padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        a: body?.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
          decorationColor: colors.primary,
        ),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: colors.onSurface,
          backgroundColor: colors.surfaceContainerHigh,
        ),
        codeblockDecoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: body?.copyWith(color: colors.onSurfaceVariant),
        blockquoteDecoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        blockquotePadding: const EdgeInsets.all(12),
        tableBorder: TableBorder.all(color: colors.outlineVariant),
        tableHead: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        tableBody: body,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
        blockSpacing: 9,
        listIndent: 22,
      ),
    );
  }
}

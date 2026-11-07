import 'package:flutter/material.dart';

import '../domain/rating_format.dart';
import '../../../l10n/l10n_ext.dart';

/// Provider-supplied rating displayed with a distinct, accessible color role.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) {
    final displayRating = formatCompactRating(rating);
    if (displayRating == null) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFFFDA92) : const Color(0xFF744500);
    final background = dark ? const Color(0xFF423015) : const Color(0xFFFFEDCA);
    return Semantics(
      label: context.l10n.providerRating(displayRating),
      child: Chip(
        avatar: Icon(Icons.star_rounded, color: foreground, size: 18),
        label: Text(
          context.l10n.ratingLabel(displayRating),
          style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        ),
        backgroundColor: background,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

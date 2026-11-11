import 'package:flutter/material.dart';

import '../../../shared/formatting/count_format.dart';

/// An inset channel number integrated into the bottom edge of a Live TV card.
/// The contour is decorative; the card remains the only interactive target.
class LiveChannelNumberNotch extends StatelessWidget {
  const LiveChannelNumberNotch({super.key, required this.number})
    : assert(number > 0);

  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return SizedBox(
      key: const Key('liveChannelNumberNotch'),
      height: 19,
      child: CustomPaint(
        painter: _ChannelNotchPainter(
          outlineColor: scheme.outlineVariant.withValues(
            alpha: isDark ? 0.75 : 0.65,
          ),
          insetColor: scheme.onSurface.withValues(alpha: isDark ? 0.04 : 0.025),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep even very long, provider-supplied numbers inside the card.
            final numberWidth = (constraints.maxWidth * 0.52)
                .clamp(0.0, 106.0)
                .toDouble();

            return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: SizedBox(
                  width: numberWidth,
                  height: 15,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatChannelNumber(number),
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints a shallow raised arch, rather than a floating pill or button.
/// The path scales with the card width and requires no additional layer.
class _ChannelNotchPainter extends CustomPainter {
  const _ChannelNotchPainter({
    required this.outlineColor,
    required this.insetColor,
  });

  final Color outlineColor;
  final Color insetColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = size.width / 2;
    final halfSpan = (size.width * 0.23).clamp(0.0, 44.0).toDouble();
    final halfCrown = (size.width * 0.11).clamp(0.0, 21.0).toDouble();
    final bottom = size.height - 0.5;
    const top = 2.5;
    final leftFoot = center - halfSpan;
    final rightFoot = center + halfSpan;
    final leftCrown = center - halfCrown;
    final rightCrown = center + halfCrown;
    final shoulder = (leftCrown - leftFoot) / 2;

    // Follow the existing bottom border so the inset has no floating ends.
    // Horizontal tangents at the feet and crown avoid pointed shoulders.
    final contour = Path()
      ..moveTo(0, bottom)
      ..lineTo(leftFoot, bottom)
      ..cubicTo(
        leftFoot + shoulder,
        bottom,
        leftCrown - shoulder,
        top,
        leftCrown,
        top,
      )
      ..lineTo(rightCrown, top)
      ..cubicTo(
        rightCrown + shoulder,
        top,
        rightFoot - shoulder,
        bottom,
        rightFoot,
        bottom,
      )
      ..lineTo(size.width, bottom);

    final inset = Path.from(contour)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(inset, Paint()..color = insetColor);
    canvas.drawPath(
      contour,
      Paint()
        ..color = outlineColor
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ChannelNotchPainter oldDelegate) =>
      outlineColor != oldDelegate.outlineColor ||
      insetColor != oldDelegate.insetColor;
}

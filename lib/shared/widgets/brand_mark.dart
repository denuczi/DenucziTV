import 'package:flutter/material.dart';

/// A single, correctly matted brand asset for light/dark mode and HiDPI.
/// The rounded badge is part of the artwork; clipping it again damages edges.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final pixelSize = (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 1024)
        .toInt();
    return Semantics(
      label: 'DenucziTV logo',
      image: true,
      child: Image.asset(
        'assets/branding/denuczitv_app_icon.png',
        width: size,
        height: size,
        cacheWidth: pixelSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}

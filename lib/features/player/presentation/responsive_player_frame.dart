import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Resizes the video region according to both available width and height.
/// Prevents fixed-aspect video layouts from overflowing maximized windows.
class ResponsivePlayerFrame extends StatelessWidget {
  const ResponsivePlayerFrame({
    super.key,
    required this.header,
    required this.video,
  });

  final Widget header;
  final Widget video;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = math.max(0.0, math.min(1180.0, viewport.width - 32.0));
    final height = math.max(
      0.0,
      math.min(viewport.height - 32.0, width * 9 / 16 + 58.0),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.black,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            SizedBox(height: 58, child: header),
            Expanded(child: ClipRect(child: video)),
          ],
        ),
      ),
    );
  }
}

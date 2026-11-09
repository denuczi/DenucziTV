import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The workspace owns the glow; the sidebar and modal surfaces stay independent.
class WorkspaceBackground extends StatelessWidget {
  const WorkspaceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => _WorkspaceGeometry(
        size: constraints.biggest,
        child: CustomPaint(
          painter: _WorkspacePainter(
            workspaceSize: constraints.biggest,
            base: theme.colorScheme.surface,
            dark: theme.brightness == Brightness.dark,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The pinned catalog header begins at the workspace origin. Paint its portion
/// of the same full-size background, rather than centering a second glow in it.
/// This stays opaque so scrolled cards cannot show through the toolbar.
class WorkspaceHeaderBackground extends StatelessWidget {
  const WorkspaceHeaderBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final geometry = context
        .dependOnInheritedWidgetOfExactType<_WorkspaceGeometry>();
    if (theme.brightness == Brightness.dark && geometry != null) {
      return CustomPaint(
        painter: _WorkspacePainter(
          workspaceSize: geometry.size,
          base: theme.colorScheme.surface,
          dark: true,
        ),
      );
    }
    // Preserve the existing header in light mode and standalone catalog views.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surfaceContainerLow,
            theme.colorScheme.surface,
          ],
        ),
      ),
    );
  }
}

class _WorkspaceGeometry extends InheritedWidget {
  const _WorkspaceGeometry({required this.size, required super.child});

  final Size size;

  @override
  bool updateShouldNotify(_WorkspaceGeometry oldWidget) =>
      size != oldWidget.size;
}

class _WorkspacePainter extends CustomPainter {
  const _WorkspacePainter({
    required this.workspaceSize,
    required this.base,
    required this.dark,
  });

  final Size workspaceSize;
  final Color base;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = base);
    if (!dark || workspaceSize.isEmpty) return;

    // Keep the site's 560px circular glow, with its opacity reduced by 30%.
    // A fixed logical radius keeps the glow circular on wide desktop windows.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          workspaceSize.center(Offset.zero),
          560,
          const [Color.fromRGBO(214, 18, 40, 0.14), Color(0x00D61228)],
        ),
    );
  }

  @override
  bool shouldRepaint(_WorkspacePainter oldDelegate) =>
      workspaceSize != oldDelegate.workspaceSize ||
      base != oldDelegate.base ||
      dark != oldDelegate.dark;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../application/update_controller.dart';
import 'update_dialog.dart';

/// Remembers interaction even if a critical route closes before HTTP completes.
class UpdateRouteObserver extends NavigatorObserver {
  bool enteredAnotherRoute = false;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) enteredAnotherRoute = true;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    enteredAnotherRoute = true;
  }
}

class StartupUpdateListener extends StatefulWidget {
  const StartupUpdateListener({
    super.key,
    required this.updates,
    required this.routes,
    required this.child,
  });
  final UpdateController updates;
  final UpdateRouteObserver routes;
  final Widget child;
  @override
  State<StartupUpdateListener> createState() => _StartupUpdateListenerState();
}

class _StartupUpdateListenerState extends State<StartupUpdateListener> {
  AppController? _app;

  bool get _critical =>
      _app?.connecting == true ||
      _app?.restoringAccount == true ||
      (_app?.downloads.activeCount ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppController?>();
    _app?.addListener(_observeActivity);
    _app?.downloads.addListener(_observeActivity);
    _observeActivity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_check());
    });
  }

  void _observeActivity() {
    // Automatic account restoration is part of normal startup. It blocks a
    // prompt while active, but does not permanently suppress a later safe result.
    final manualAuthentication =
        _app?.connecting == true && _app?.restoringAccount != true;
    final transferring = (_app?.downloads.activeCount ?? 0) > 0;
    if (manualAuthentication || transferring) {
      widget.updates.suppressStartupPrompt();
    }
  }

  Future<void> _check() async {
    final release = await widget.updates.checkAtStartup();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final safe =
          release != null &&
          !_critical &&
          !widget.routes.enteredAnotherRoute &&
          ModalRoute.of(context)?.isCurrent == true &&
          !widget.updates.dialogGuard.isBusy;
      if (widget.updates.claimStartupPrompt(safe: safe) && release != null) {
        unawaited(showStableUpdateDialog(context, widget.updates, release));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _app?.removeListener(_observeActivity);
    _app?.downloads.removeListener(_observeActivity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, _) {
      widget.updates.suppressStartupPrompt();
      return KeyEventResult.ignored;
    },
    child: Listener(
      onPointerDown: (_) => widget.updates.suppressStartupPrompt(),
      onPointerSignal: (_) => widget.updates.suppressStartupPrompt(),
      child: widget.child,
    ),
  );
}

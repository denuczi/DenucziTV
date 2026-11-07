import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/app_controller.dart';
import '../../../core/models/app_identity.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../shared/notifications/app_notice.dart';
import '../../../shared/widgets/brand_mark.dart';
import '../../accounts/presentation/accounts_page.dart';
import '../../personal_library/presentation/my_library_page.dart';
import '../../downloads/presentation/downloads_page.dart';
import '../../downloads/data/download_manager.dart';
import '../../downloads/domain/download_task.dart';
import '../../library/domain/media_models.dart';
import '../../library/presentation/library_page.dart';
import '../../settings/presentation/settings_page.dart';

enum _Workspace { library, myLibrary, accounts, downloads, settings }

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  _Workspace _workspace = _Workspace.library;
  late DownloadManager _downloads;
  final Map<String, DownloadStatus> _terminalNotified = {};

  @override
  void initState() {
    super.initState();
    _downloads = context.read<AppController>().downloads;
    for (final task in _downloads.tasks) {
      if (task.status == DownloadStatus.completed ||
          task.status == DownloadStatus.failed) {
        _terminalNotified[task.id] = task.status;
      }
    }
    _downloads.addListener(_onDownloadChanged);
  }

  void _onDownloadChanged() {
    final tasks = _downloads.tasks;
    final activeIds = tasks.map((task) => task.id).toSet();
    _terminalNotified.removeWhere((id, _) => !activeIds.contains(id));
    for (final task in tasks) {
      final completed = task.status == DownloadStatus.completed;
      final failed = task.status == DownloadStatus.failed;
      if (!(completed || failed)) {
        _terminalNotified.remove(task.id);
        continue;
      }
      if (_terminalNotified[task.id] == task.status) {
        continue;
      }
      _terminalNotified[task.id] = task.status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        AppNotice.show(
          context,
          level: completed ? NoticeLevel.success : NoticeLevel.error,
          title: completed
              ? context.l10n.downloadComplete
              : context.l10n.downloadFailed,
          message: completed ? task.title : (task.message ?? task.title),
          actionLabel: context.l10n.downloads,
          onAction: () {
            if (!mounted) {
              return;
            }
            Navigator.of(
              context,
              rootNavigator: true,
            ).popUntil((route) => route.isFirst);
            setState(() => _workspace = _Workspace.downloads);
          },
        );
      });
    }
  }

  @override
  void dispose() {
    _downloads.removeListener(_onDownloadChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;
          return Row(
            children: [
              Container(
                width: narrow ? 68 : 228,
                decoration: BoxDecoration(
                  gradient: AppPalette.sidebarGradient(
                    Theme.of(context).brightness,
                  ),
                  border: Border(
                    right: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: _SidePanel(
                  narrow: narrow,
                  app: app,
                  workspace: _workspace,
                  onNavigate: (workspace, kind) {
                    setState(() => _workspace = workspace);
                    if (kind != null && kind != app.kind) {
                      unawaited(app.selectKind(kind));
                    }
                  },
                ),
              ),
              Expanded(
                child: switch (_workspace) {
                  _Workspace.library => const LibraryPage(),
                  _Workspace.accounts => const AccountsPage(),
                  _Workspace.myLibrary => const MyLibraryPage(),
                  _Workspace.downloads => const DownloadsPage(),
                  _Workspace.settings => const SettingsPage(),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.narrow,
    required this.app,
    required this.workspace,
    required this.onNavigate,
  });

  final bool narrow;
  final AppController app;
  final _Workspace workspace;
  final void Function(_Workspace workspace, LibraryKind? kind) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(narrow ? 5 : 9, 18, 0, 28),
            child: Row(
              children: [
                const BrandMark(size: 36),
                if (!narrow) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      AppIdentity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (!narrow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 0, 10),
                    child: Text(
                      context.l10n.library,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                _NavItem(
                  narrow: narrow,
                  id: 'live-tv',
                  label: context.l10n.liveTv,
                  icon: Icons.live_tv_outlined,
                  selected:
                      workspace == _Workspace.library &&
                      app.kind == LibraryKind.live,
                  onTap: () => onNavigate(_Workspace.library, LibraryKind.live),
                ),
                _NavItem(
                  narrow: narrow,
                  id: 'movies',
                  label: context.l10n.movies,
                  icon: Icons.movie_outlined,
                  selected:
                      workspace == _Workspace.library &&
                      app.kind == LibraryKind.movies,
                  onTap: () =>
                      onNavigate(_Workspace.library, LibraryKind.movies),
                ),
                _NavItem(
                  narrow: narrow,
                  id: 'series',
                  label: context.l10n.series,
                  icon: Icons.video_library_outlined,
                  selected:
                      workspace == _Workspace.library &&
                      app.kind == LibraryKind.series,
                  onTap: () =>
                      onNavigate(_Workspace.library, LibraryKind.series),
                ),
                _NavItem(
                  narrow: narrow,
                  id: 'my-library',
                  label: context.l10n.myLibrary,
                  icon: Icons.bookmarks_outlined,
                  selected: workspace == _Workspace.myLibrary,
                  onTap: () => onNavigate(_Workspace.myLibrary, null),
                ),
                const SizedBox(height: 13),
                const Divider(),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: app.downloads,
                  builder: (context, _) => _NavItem(
                    narrow: narrow,
                    id: 'downloads',
                    label: context.l10n.downloads,
                    icon: Icons.download_outlined,
                    selected: workspace == _Workspace.downloads,
                    onTap: () => onNavigate(_Workspace.downloads, null),
                    badge: app.downloads.activeCount,
                  ),
                ),
                _NavItem(
                  narrow: narrow,
                  id: 'settings',
                  label: context.l10n.settings,
                  icon: Icons.settings_outlined,
                  selected: workspace == _Workspace.settings,
                  onTap: () => onNavigate(_Workspace.settings, null),
                ),
              ],
            ),
          ),
          const Divider(),
          Tooltip(
            message: context.l10n.manageAccounts,
            child: Material(
              color: workspace == _Workspace.accounts
                  ? scheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(11),
                onTap: () => onNavigate(_Workspace.accounts, null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle_outlined, size: 25),
                      if (!narrow) ...[
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.activeAccount?.label ??
                                    context.l10n.noAccountSelected,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                app.activeAccount == null
                                    ? context.l10n.manageProviders
                                    : context.l10n.connectedManage,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 17),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!narrow)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
              child: Text(
                context.l10n.versionLabel(AppIdentity.version),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single destination in the sidebar.
///
/// The selected destination uses a persistent surface. Hover and keyboard
/// focus are transient states and must not look like a second selection.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.narrow,
    required this.label,
    required this.id,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final bool narrow;
  final String label;
  final String id;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Semantics(
        key: Key('navigation-${widget.id}'),
        selected: widget.selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: Tooltip(
          message: widget.narrow ? widget.label : '',
          child: Material(
            color: widget.selected
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: _focused
                  ? BorderSide(color: scheme.primary, width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: radius,
              onFocusChange: (focused) {
                if (_focused != focused && mounted) {
                  setState(() => _focused = focused);
                }
              },
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return scheme.onSurface.withValues(alpha: 0.08);
                }
                if (states.contains(WidgetState.hovered)) {
                  return scheme.onSurface.withValues(alpha: 0.04);
                }
                // Keyboard focus is indicated by the outline, not a fill.
                return Colors.transparent;
              }),
              onTap: () {
                // A previously clicked item must not keep a selected-looking
                // focus overlay after navigating to another section.
                FocusManager.instance.primaryFocus?.unfocus();
                widget.onTap();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.narrow ? 12 : 13,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 21,
                      color: widget.selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    if (!widget.narrow) ...[
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (widget.badge > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${widget.badge}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

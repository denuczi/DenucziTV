import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_languages.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../l10n/app_error_localizations.dart';
import '../../../core/models/app_controller.dart';
import '../../../core/network/user_agent.dart';
import '../../../shared/notifications/app_notice.dart';
import '../../../shared/widgets/brand_mark.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _userAgent;
  String? _message;
  bool _saving = false;
  bool _messageSucceeded = false;

  @override
  void initState() {
    super.initState();
    _userAgent = TextEditingController(
      text: context.read<AppController>().userAgent,
    );
  }

  @override
  void dispose() {
    _userAgent.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
      _messageSucceeded = false;
    });
    try {
      await context.read<AppController>().updateUserAgent(_userAgent.text);
      if (mounted) {
        setState(() {
          _message = context.l10n.userAgentSaved;
          _messageSucceeded = true;
        });
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() => _message = localizeAppError(context, error.message));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = context.l10n.userAgentSaveFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _updatePreference(
    Future<void> Function(bool) update,
    bool value,
  ) async {
    try {
      await update(value);
    } catch (_) {
      if (mounted) {
        _report(context, context.l10n.updatePreferenceFailed);
      }
    }
  }

  Future<void> _openGitHub() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://github.com/denuczi/DenucziTV'),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) {
        return;
      }
      if (!opened) {
        _report(context, context.l10n.githubOpenFailed);
      }
    } catch (_) {
      if (mounted) {
        _report(context, context.l10n.githubOpenFailed);
      }
    }
  }

  void _report(BuildContext context, String message) {
    AppNotice.show(
      context,
      level: NoticeLevel.error,
      title: context.l10n.settingsCouldNotSave,
      message: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 65),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.settings,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.settingsSubtitle,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                _Section(
                  icon: Icons.palette_outlined,
                  title: context.l10n.appearance,
                  subtitle: context.l10n.appearanceHelp,
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(context.l10n.system),
                            icon: Icon(Icons.settings_suggest_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(context.l10n.light),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(context.l10n.dark),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {app.themeMode},
                        onSelectionChanged: (value) async {
                          try {
                            await app.updateThemeMode(value.first);
                          } catch (_) {
                            if (context.mounted) {
                              _report(
                                context,
                                context.l10n.appearanceSaveFailed,
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  icon: Icons.translate_outlined,
                  title: context.l10n.language,
                  subtitle: context.l10n.languageHelp,
                  child: Center(
                    child: SizedBox(
                      width: 560,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 560,
                          child: SegmentedButton<String>(
                            key: const Key('languageSelector'),
                            showSelectedIcon: true,
                            segments: [
                              ButtonSegment(
                                value: 'system',
                                label: Text(context.l10n.systemLanguage),
                              ),
                              for (final language in AppLanguages.options)
                                ButtonSegment(
                                  value: language.code,
                                  label: Text(language.nativeName),
                                ),
                            ],
                            selected: {app.languageCode ?? 'system'},
                            onSelectionChanged: (values) async {
                              try {
                                final value = values.first;
                                await app.updateLanguage(
                                  value == 'system' ? null : value,
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  _report(
                                    context,
                                    context.l10n.languageSaveFailed,
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  icon: Icons.tune_outlined,
                  title: context.l10n.mediaActions,
                  subtitle: app.canShareLinks
                      ? context.l10n.mediaActionsHelp
                      : context.l10n.mediaActionsProtectedHelp,
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        key: const Key('showDownloadControls'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.downloadButtons),
                        subtitle: Text(context.l10n.downloadButtonsHelp),
                        value: app.showDownloadControls,
                        onChanged: (enabled) async {
                          await _updatePreference(
                            app.updateDownloadControls,
                            enabled,
                          );
                        },
                      ),
                      const Divider(height: 12),
                      SwitchListTile.adaptive(
                        key: const Key('showCopyLinkControls'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.copyStreamLink),
                        subtitle: Text(context.l10n.copyStreamLinkHelp),
                        value: app.copyLinksAvailable,
                        onChanged: app.canShareLinks
                            ? (enabled) => _updatePreference(
                                app.updateCopyLinkControls,
                                enabled,
                              )
                            : null,
                      ),
                      const Divider(height: 12),
                      SwitchListTile.adaptive(
                        key: const Key('showExportM3u'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.exportM3u),
                        subtitle: Text(context.l10n.exportM3uHelp),
                        value: app.exportM3uAvailable,
                        onChanged: app.canShareLinks
                            ? (enabled) => _updatePreference(
                                app.updateExportM3u,
                                enabled,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  icon: Icons.public_rounded,
                  title: context.l10n.networkIdentity,
                  subtitle: context.l10n.networkIdentityHelp,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.l10n.globalUserAgent(
                          app.customUserAgent
                              ? context.l10n.custom
                              : context.l10n.automatic,
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('globalUserAgent'),
                        controller: _userAgent,
                        maxLength: 256,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: UserAgent.defaultValue,
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.automaticUserAgentHelp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.userAgentNewRequests,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Keep the actions the same size and stack them when the
                          // settings panel becomes too narrow for both buttons.
                          final compact = constraints.maxWidth < 580;
                          final buttonWidth = compact
                              ? constraints.maxWidth
                              : 280.0;
                          return Wrap(
                            alignment: compact
                                ? WrapAlignment.center
                                : WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: buttonWidth,
                                height: 48,
                                child: FilledButton.icon(
                                  key: const Key('saveUserAgentButton'),
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(
                                    _saving
                                        ? context.l10n.saving
                                        : context.l10n.saveUserAgent,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: buttonWidth,
                                height: 48,
                                child: OutlinedButton(
                                  key: const Key('resetUserAgentButton'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () async {
                                          try {
                                            await context
                                                .read<AppController>()
                                                .resetUserAgent();
                                            if (!context.mounted) {
                                              return;
                                            }
                                            setState(() {
                                              _userAgent.text =
                                                  UserAgent.defaultValue;
                                              _message = context
                                                  .l10n
                                                  .userAgentResetSuccess;
                                              _messageSucceeded = true;
                                            });
                                          } catch (_) {
                                            if (context.mounted) {
                                              _report(
                                                context,
                                                context
                                                    .l10n
                                                    .userAgentResetFailed,
                                              );
                                            }
                                          }
                                        },
                                  child: Text(context.l10n.restoreDefault),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _messageSucceeded
                                ? const Color(0xFF28865C)
                                : colors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  icon: Icons.shield_outlined,
                  title: context.l10n.connectionSecurity,
                  subtitle: context.l10n.connectionSecurityHelp,
                  child: Column(
                    children: [
                      _SecurityRow(
                        context.l10n.certificateVerification,
                        context.l10n.certificateVerificationHelp,
                      ),
                      const SizedBox(height: 16),
                      _SecurityRow(
                        context.l10n.savedCredentials,
                        context.l10n.savedCredentialsHelp,
                      ),
                      const SizedBox(height: 16),
                      _SecurityRow(
                        context.l10n.directLinks,
                        context.l10n.directLinksHelp,
                      ),
                      const Divider(height: 30),
                      SwitchListTile.adaptive(
                        key: const Key('allowHttpsToHttpDownloadRedirects'),
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.warning_amber_rounded,
                          color: colors.tertiary,
                        ),
                        title: Text(context.l10n.allowInsecureRedirects),
                        subtitle: Text(context.l10n.allowInsecureRedirectsHelp),
                        value: app.allowInsecureDownloadRedirects,
                        onChanged: (enabled) => _updatePreference(
                          app.updateAllowInsecureDownloadRedirects,
                          enabled,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                const Divider(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const BrandMark(size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DenucziTV', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 3),
                          Text(
                            context.l10n.createdBy,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'github.com/denuczi/DenucziTV',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openGitHub,
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: Text(context.l10n.visitGitHub),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A colored DecoratedBox between SwitchListTile and Material hides ink
    // effects and triggers a Flutter framework assertion. Paint the section
    // background on Material itself so its interactive states remain visible.
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 25),
            child,
          ],
        ),
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.check_circle_outline,
        size: 20,
        color: Color(0xFF329D70),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 5),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

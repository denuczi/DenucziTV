import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_error_localizations.dart';
import '../../../l10n/l10n_ext.dart';

import '../../../core/models/account.dart';
import '../../../core/models/app_controller.dart';
import '../../../core/network/server_address.dart';
import '../../../core/network/xtream_playlist_link.dart';
import '../data/protected_link_resolver.dart';

class ConnectDialog extends StatefulWidget {
  const ConnectDialog({
    super.key,
    this.initialMethod = AccountConnectionType.xtream,
    this.initialSource = '',
    this.initialLabel = '',
  });

  final AccountConnectionType initialMethod;
  final String initialSource;
  final String initialLabel;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();
  String? _error;
  String _previousUrlInput = '';
  bool _submitted = false;
  AccountConnectionType _method = AccountConnectionType.xtream;
  bool get _protected => _method == AccountConnectionType.protectedSingleLink;
  bool get _playlist => _method == AccountConnectionType.m3u;

  @override
  void initState() {
    super.initState();
    _method = widget.initialMethod;
    _url.text = widget.initialSource;
    _label.text = widget.initialLabel;
    _previousUrlInput = _url.text;
  }

  Future<void> _choosePlaylistFile() async {
    // Close the Flutter modal completely before showing the native chooser.
    // This avoids re-entering the dialog loop on Windows and Linux.
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final prior = _url.text;
    final label = _label.text;
    navigator.pop();
    await route?.completed;
    if (!navigator.mounted) return;
    XFile? selected;
    try {
      selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'M3U', extensions: ['m3u', 'm3u8']),
        ],
      );
    } catch (_) {
      // Reopen the form so the user can enter a URL instead.
    }
    if (!navigator.mounted) return;
    await showDialog<void>(
      context: navigator.context,
      builder: (_) => ConnectDialog(
        initialMethod: AccountConnectionType.m3u,
        initialSource: selected?.path ?? prior,
        initialLabel: label,
      ),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _label.dispose();
    super.dispose();
  }

  void _onServerUrlChanged(String value) {
    // A paste inserts multiple characters at once. Do not normalize a URL
    // while someone is still typing the username or password one character at a time.
    final bulkInsertion = _hasBulkInsertion(_previousUrlInput, value);
    _previousUrlInput = value;
    if (bulkInsertion) {
      _applyPlaylistLink(value);
    }
    setState(() {});
  }

  bool _hasBulkInsertion(String previous, String current) {
    var prefix = 0;
    while (prefix < previous.length &&
        prefix < current.length &&
        previous.codeUnitAt(prefix) == current.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < previous.length - prefix &&
        suffix < current.length - prefix &&
        previous.codeUnitAt(previous.length - 1 - suffix) ==
            current.codeUnitAt(current.length - 1 - suffix)) {
      suffix++;
    }
    return current.length - prefix - suffix > 1;
  }

  bool _applyPlaylistLink(String value) {
    if (_method != AccountConnectionType.xtream) return false;
    final link = XtreamPlaylistLink.tryParse(value);
    if (link == null) return false;
    _setFieldValue(_url, link.serverUrl);
    _setFieldValue(_username, link.username);
    _setFieldValue(_password, link.password);
    _previousUrlInput = link.serverUrl;
    return true;
  }

  void _onServerUrlSubmitted(String value) {
    if (_applyPlaylistLink(value)) {
      setState(() {});
    }
  }

  void _setFieldValue(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _connect() async {
    _applyPlaylistLink(_url.text);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitted = true;
      _error = null;
    });
    final app = context.read<AppController>();
    final connected = _playlist
        ? await app.connectPlaylist(_url.text, _label.text)
        : _protected
        ? await app.connectProtected(_label.text, _url.text)
        : await app.connect(
            AccountCredentials(
              serverUrl: _url.text,
              username: _username.text,
              password: _password.text,
              label: _label.text,
            ),
          );
    if (!mounted) {
      return;
    }
    if (connected) {
      _url.clear();
      _username.clear();
      _password.clear();
      Navigator.of(context).pop();
    } else {
      setState(
        () => _error = app.error == null
            ? context.l10n.connectionFailed
            : localizeAppError(context, app.error!),
      );
    }
    if (mounted) {
      setState(() => _submitted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.connectProvider),
      scrollable: true,
      constraints: const BoxConstraints(maxWidth: 500),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<AccountConnectionType>(
                initialValue: _method,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.connectionMethod,
                ),
                items: [
                  DropdownMenuItem(
                    value: AccountConnectionType.xtream,
                    child: Text(context.l10n.xtreamManual),
                  ),
                  DropdownMenuItem(
                    value: AccountConnectionType.m3u,
                    child: Text(context.l10n.m3uPlaylist),
                  ),
                  DropdownMenuItem(
                    value: AccountConnectionType.protectedSingleLink,
                    child: Text(context.l10n.protectedSingleLink),
                  ),
                ],
                onChanged: _submitted
                    ? null
                    : (value) => setState(() {
                        _method = value!;
                        _url.clear();
                        _previousUrlInput = '';
                        _error = null;
                      }),
              ),
              const SizedBox(height: 16),
              Text(
                _protected
                    ? context.l10n.protectedLinkHelp
                    : _playlist
                    ? context.l10n.m3uSourceHelp
                    : context.l10n.connectProviderSubtitle,
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('serverUrl'),
                controller: _url,
                autofocus: true,
                onChanged: _onServerUrlChanged,
                onFieldSubmitted: _onServerUrlSubmitted,
                decoration: InputDecoration(
                  labelText: _protected
                      ? context.l10n.protectedLink
                      : _playlist
                      ? context.l10n.m3uPlaylistSource
                      : context.l10n.serverUrl,
                  hintText: _protected
                      ? 'https://iptv.example/client/access-code'
                      : _playlist
                      ? 'https://iptv.example/playlist.m3u'
                      : 'https://provider.example:443',
                  prefixIcon: Icon(Icons.language),
                ),
                validator: (value) {
                  try {
                    if (_protected) {
                      ProtectedLinkResolver.validateUrl(value ?? '');
                    } else if (_playlist) {
                      final raw = (value ?? '').trim();
                      final uri = Uri.tryParse(raw);
                      final remote =
                          uri != null &&
                          (uri.scheme == 'http' || uri.scheme == 'https') &&
                          uri.host.isNotEmpty &&
                          uri.userInfo.isEmpty &&
                          !uri.hasFragment;
                      final local =
                          RegExp(r'\.(m3u8?|M3U8?)$').hasMatch(raw) &&
                          (raw.startsWith('/') ||
                              RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(raw));
                      if (!remote && !local) throw const FormatException();
                    } else {
                      ServerAddress.parse(value ?? '');
                    }
                    return null;
                  } catch (_) {
                    return _protected
                        ? context.l10n.protectedInvalidUrl
                        : _playlist
                        ? context.l10n.m3uInvalidSource
                        : context.l10n.invalidServerUrl;
                  }
                },
              ),
              if (_playlist) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _submitted ? null : _choosePlaylistFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(context.l10n.m3uChooseFile),
                ),
              ],
              const SizedBox(height: 12),
              if (!_protected && !_playlist)
                TextFormField(
                  key: const Key('username'),
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: context.l10n.username,
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? context.l10n.usernameRequired
                      : null,
                ),
              const SizedBox(height: 12),
              if (!_protected && !_playlist)
                TextFormField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.password,
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? context.l10n.passwordRequired
                      : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _label,
                validator: (value) => _protected && (value ?? '').trim().isEmpty
                    ? context.l10n.accountNameRequired
                    : null,
                decoration: InputDecoration(
                  labelText: _protected
                      ? context.l10n.accountName
                      : context.l10n.displayNameOptional,
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              if (_url.text.trim().startsWith('http://')) ...[
                const SizedBox(height: 12),
                Text(
                  context.l10n.httpCredentialsWarning,
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitted ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _submitted ? null : _connect,
          icon: _submitted
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login, size: 18),
          label: Text(context.l10n.connect),
        ),
      ],
    );
  }
}

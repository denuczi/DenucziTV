import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_error_localizations.dart';
import '../../../l10n/l10n_ext.dart';

import '../../../core/models/account.dart';
import '../../../core/models/app_controller.dart';
import '../../../core/network/server_address.dart';

class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key});

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
  bool _submitted = false;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitted = true;
      _error = null;
    });
    final app = context.read<AppController>();
    final connected = await app.connect(
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
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.connectProviderSubtitle),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('serverUrl'),
                controller: _url,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.l10n.serverUrl,
                  hintText: 'https://provider.example:443',
                  prefixIcon: Icon(Icons.language),
                ),
                validator: (value) {
                  try {
                    ServerAddress.parse(value ?? '');
                    return null;
                  } catch (_) {
                    return context.l10n.invalidServerUrl;
                  }
                },
              ),
              const SizedBox(height: 12),
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
                decoration: InputDecoration(
                  labelText: context.l10n.displayNameOptional,
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

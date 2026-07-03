import 'package:flutter/material.dart';

import '../app_state.dart';
import 'format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _owner;
  late final TextEditingController _repo;
  late final TextEditingController _branch;
  final _token = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    final c = widget.state.config!;
    _owner = TextEditingController(text: c.owner);
    _repo = TextEditingController(text: c.repo);
    _branch = TextEditingController(text: c.branch);
  }

  @override
  void dispose() {
    for (final c in [_owner, _repo, _branch, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveConnection() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final err = await widget.state.updateConnection(
      owner: _owner.text.trim(),
      repo: _repo.text.trim(),
      branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
      token: _token.text.trim().isEmpty
          ? widget.state.config!.token
          : _token.text.trim(),
    );
    setState(() {
      _busy = false;
      _messageIsError = err != null;
      _message = err ?? 'Verbindung gespeichert.';
      if (err == null) _token.clear();
    });
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App zurücksetzen?'),
        content: const Text(
            'Entfernt Zugangsdaten, Schlüssel und alle lokalen Daten von '
            'diesem Gerät. Die verschlüsselten ToDos im GitHub-Repository '
            'bleiben erhalten und können mit der Passphrase wieder '
            'eingerichtet werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.state.resetApp();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Synchronisation',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(state.lastSync == null
                    ? 'Noch nicht synchronisiert.'
                    : 'Letzter Sync: ${formatDateTime(state.lastSync!)}'),
                if (state.pendingCount > 0)
                  Text('${state.pendingCount} Änderung(en) ausstehend'),
                if (state.syncError != null)
                  Text(state.syncError!,
                      style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed:
                        state.syncing ? null : () => state.syncNow(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Jetzt synchronisieren'),
                  ),
                ),
                const Divider(height: 40),
                Text('GitHub-Verbindung',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _owner,
                      decoration: const InputDecoration(
                          labelText: 'Besitzer',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _repo,
                      decoration: const InputDecoration(
                          labelText: 'Repository',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _branch,
                  decoration: const InputDecoration(
                      labelText: 'Branch', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _token,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Neues Token (leer = unverändert)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton(
                    onPressed: _busy ? null : _saveConnection,
                    child: const Text('Prüfen & speichern'),
                  ),
                  const SizedBox(width: 12),
                  if (_message != null)
                    Expanded(
                      child: Text(_message!,
                          style: TextStyle(
                              color: _messageIsError
                                  ? Colors.red
                                  : Colors.green)),
                    ),
                ]),
                const Divider(height: 40),
                Text('Sicherheit',
                    style: Theme.of(context).textTheme.titleLarge),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Schlüssel auf diesem Gerät speichern'),
                  subtitle: const Text(
                      'Aus: Passphrase wird bei jedem Start abgefragt.'),
                  value: state.config!.rememberKey,
                  onChanged: (v) => state.setRememberKey(v),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('App zurücksetzen'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

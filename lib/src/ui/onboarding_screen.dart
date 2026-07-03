import 'package:flutter/material.dart';

import '../app_state.dart';

/// Ersteinrichtung: GitHub-Zugangsdaten und Verschlüsselungs-Passphrase.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.state});

  final AppState state;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  final _token = TextEditingController();
  final _passphrase = TextEditingController();
  final _passphrase2 = TextEditingController();

  bool _tokenVisible = false;
  bool _rememberKey = true;
  bool _busy = false;
  String? _testResult;
  bool _testOk = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Vom Installationsskript hinterlegte Erstkonfiguration übernehmen.
    widget.state.loadProvision().then((prov) {
      if (prov == null || !mounted) return;
      setState(() {
        _owner.text = prov['owner'] as String? ?? _owner.text;
        _repo.text = prov['repo'] as String? ?? _repo.text;
        _branch.text = prov['branch'] as String? ?? _branch.text;
        _token.text = prov['token'] as String? ?? _token.text;
        final pass = prov['passphrase'] as String?;
        if (pass != null) {
          _passphrase.text = pass;
          _passphrase2.text = pass;
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_owner, _repo, _branch, _token, _passphrase, _passphrase2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _testResult = null;
    });
    final err = await widget.state.testConnection(
      owner: _owner.text.trim(),
      repo: _repo.text.trim(),
      branch: _branch.text.trim(),
      token: _token.text.trim(),
    );
    setState(() {
      _busy = false;
      _testOk = err == null;
      _testResult = err ?? 'Verbindung erfolgreich!';
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.completeOnboarding(
        owner: _owner.text.trim(),
        repo: _repo.text.trim(),
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        token: _token.text.trim(),
        passphrase: _passphrase.text,
        rememberKey: _rememberKey,
      );
      // Erfolg: main.dart wechselt automatisch zum HomeScreen.
    } on OnboardingException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Einrichtung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einrichtung')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('1. GitHub-Repository',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                    'Privates Repository, das die verschlüsselten ToDos '
                    'speichert. Benötigt wird ein Fine-grained Personal '
                    'Access Token mit Lese-/Schreibrecht auf "Contents" — '
                    'nur für dieses eine Repository.'),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _owner,
                      decoration: const InputDecoration(
                          labelText: 'Besitzer',
                          hintText: 'z. B. SebastianWeber',
                          border: OutlineInputBorder()),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _repo,
                      decoration: const InputDecoration(
                          labelText: 'Repository',
                          hintText: 'z. B. encrypted-todo-app-backend',
                          border: OutlineInputBorder()),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _branch,
                  decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _token,
                  obscureText: !_tokenVisible,
                  decoration: InputDecoration(
                    labelText: 'Personal Access Token',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_tokenVisible
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _tokenVisible = !_tokenVisible),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Verbindung testen'),
                  ),
                  const SizedBox(width: 12),
                  if (_testResult != null)
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                            color: _testOk ? Colors.green : Colors.red),
                      ),
                    ),
                ]),
                const Divider(height: 40),
                Text('2. Verschlüsselung',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                    'Alle ToDos werden mit dieser Passphrase verschlüsselt '
                    '(AES-256). Bei einem bereits eingerichteten Repository '
                    'muss die vorhandene Passphrase eingegeben werden.'),
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'Wichtig: Ohne Passphrase gibt es keinen Zugriff auf '
                        'die Daten. Es existiert keine Wiederherstellung — '
                        'Passphrase sicher aufbewahren!'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Passphrase',
                      border: OutlineInputBorder()),
                  validator: (v) => v == null || v.length < 8
                      ? 'Mindestens 8 Zeichen'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passphrase2,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Passphrase bestätigen',
                      border: OutlineInputBorder()),
                  validator: (v) =>
                      v != _passphrase.text ? 'Stimmt nicht überein' : null,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Schlüssel auf diesem Gerät speichern'),
                  subtitle: const Text(
                      'Aus: Passphrase wird bei jedem Start abgefragt.'),
                  value: _rememberKey,
                  onChanged: (v) => setState(() => _rememberKey = v),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock),
                  label: const Text('Einrichten'),
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

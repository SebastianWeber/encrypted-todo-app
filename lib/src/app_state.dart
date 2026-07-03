import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';

import 'crypto/crypto_service.dart';
import 'models/recurrence_logic.dart';
import 'models/todo.dart';
import 'notifications/notification_service.dart';
import 'settings/app_config.dart';
import 'storage/local_store.dart';
import 'sync/github_api.dart';
import 'sync/sync_service.dart';

/// Zentraler App-Zustand: Konfiguration, lokaler Store, Sync, Erinnerungen.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({
    required this.configStore,
    required this.baseDir,
    required this.notifications,
  });

  final AppConfigStore configStore;

  /// Applikationsdatenverzeichnis (path_provider).
  final String baseDir;
  final NotificationService notifications;
  final CryptoService crypto = CryptoService();

  AppConfig? config;
  GithubApi? _api;
  LocalStore? _store;
  SyncService? _sync;
  SecretKey? _key;
  Timer? _autoSyncTimer;

  bool initialized = false;
  bool syncing = false;
  String? syncError;
  SyncResult? lastSyncResult;

  bool get isConfigured => config != null;

  /// Passphrase wird nicht gespeichert und muss eingegeben werden.
  bool get needsUnlock =>
      config != null && _key == null;

  List<Todo> get todos => _store?.todos ?? const [];
  int get pendingCount => _store?.pendingCount ?? 0;
  DateTime? get lastSync => _store?.lastSync;

  // ------------------------------------------------------------ Start

  /// Beim Zurückkehren in den Vordergrund sofort synchronisieren — sonst
  /// arbeitet man auf einem veralteten Stand und überschreibt beim nächsten
  /// Speichern Änderungen anderer Geräte.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow(silent: true));
    }
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    config = await configStore.load();
    if (config != null && config!.masterKeyB64.isNotEmpty) {
      _key = SecretKey(base64Decode(config!.masterKeyB64));
      await _openStore();
    }
    initialized = true;
    notifyListeners();
    if (_key != null) unawaited(syncNow(silent: true));
  }

  Future<void> _openStore() async {
    final c = config!;
    _api = GithubApi(GithubConfig(
        owner: c.owner, repo: c.repo, branch: c.branch, token: c.token));
    _store = LocalStore(baseDir: '$baseDir/data', crypto: crypto, key: _key!);
    await _store!.init();
    _sync = SyncService(store: _store!, api: _api!, crypto: crypto, key: _key!);
    await notifications.init();
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
        const Duration(minutes: 15), (_) => syncNow(silent: true));
  }

  // ------------------------------------------------------ Einrichtung

  /// Prüft GitHub-Zugangsdaten; liefert null bei Erfolg, sonst Fehlertext.
  Future<String?> testConnection({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    try {
      final api = GithubApi(GithubConfig(
          owner: owner, repo: repo, branch: branch, token: token));
      await api.testConnection();
      return null;
    } on GithubApiException catch (e) {
      if (e.isNotFound) {
        return 'Repository nicht gefunden — Name prüfen und sicherstellen, '
            'dass das Token Zugriff auf dieses Repo hat.';
      }
      if (e.isUnauthorized) return 'Token ungültig oder ohne Berechtigung.';
      return e.toString();
    } catch (e) {
      return 'Verbindung fehlgeschlagen: $e';
    }
  }

  /// Schließt die Einrichtung ab. Wirft [OnboardingException] mit
  /// verständlicher Meldung bei Problemen.
  Future<void> completeOnboarding({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required String passphrase,
    required bool rememberKey,
  }) async {
    final api = GithubApi(GithubConfig(
        owner: owner, repo: repo, branch: branch, token: token));
    try {
      await api.testConnection();
    } on GithubApiException catch (e) {
      throw OnboardingException(e.isNotFound
          ? 'Repository nicht gefunden.'
          : 'GitHub-Zugriff fehlgeschlagen: ${e.message}');
    }

    var params = await SyncService.fetchMeta(api);
    final isFresh = params == null;
    params ??= CryptoParams.generate();
    final key = await crypto.deriveKey(passphrase, params);

    if (isFresh) {
      await SyncService.initializeRemote(api, crypto, key, params);
    } else if (!await SyncService.verifyKey(api, crypto, key)) {
      throw const OnboardingException(
          'Passphrase falsch — sie passt nicht zu den Daten im Repository.');
    }

    config = AppConfig(
      owner: owner,
      repo: repo,
      branch: branch,
      token: token,
      masterKeyB64: base64Encode(await key.extractBytes()),
      cryptoParams: params,
      rememberKey: rememberKey,
    );
    await configStore.save(config!);
    _key = key;
    await _openStore();
    notifyListeners();
    unawaited(syncNow(silent: true));
  }

  /// Entsperren bei nicht gespeicherter Passphrase.
  /// Liefert null bei Erfolg, sonst Fehlertext.
  Future<String?> unlock(String passphrase) async {
    final key = await crypto.deriveKey(passphrase, config!.cryptoParams);
    // Lokal verifizieren (offlinefähig); ohne lokale Daten gegen Remote.
    final probeStore =
        LocalStore(baseDir: '$baseDir/data', crypto: crypto, key: key);
    try {
      await probeStore.init();
    } on DecryptionFailedException {
      return 'Passphrase falsch.';
    }
    _key = key;
    await _openStore();
    notifyListeners();
    unawaited(syncNow(silent: true));
    return null;
  }

  /// Ändert die GitHub-Verbindungsdaten (Schlüssel bleibt unverändert).
  /// Liefert null bei Erfolg, sonst Fehlertext.
  Future<String?> updateConnection({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    final err = await testConnection(
        owner: owner, repo: repo, branch: branch, token: token);
    if (err != null) return err;
    config = AppConfig(
      owner: owner,
      repo: repo,
      branch: branch,
      token: token,
      masterKeyB64: config!.masterKeyB64,
      cryptoParams: config!.cryptoParams,
      rememberKey: config!.rememberKey,
    );
    await configStore.save(config!);
    await _openStore();
    notifyListeners();
    unawaited(syncNow(silent: true));
    return null;
  }

  Future<void> setRememberKey(bool remember) async {
    config = AppConfig(
      owner: config!.owner,
      repo: config!.repo,
      branch: config!.branch,
      token: config!.token,
      masterKeyB64:
          remember ? base64Encode(await _key!.extractBytes()) : '',
      cryptoParams: config!.cryptoParams,
      rememberKey: remember,
    );
    await configStore.save(config!);
    notifyListeners();
  }

  /// Setzt die App vollständig zurück (Konfiguration + lokale Daten).
  /// Die Daten im GitHub-Repo bleiben unangetastet.
  Future<void> resetApp() async {
    _autoSyncTimer?.cancel();
    await _store?.wipe();
    await configStore.clear();
    config = null;
    _key = null;
    _store = null;
    _sync = null;
    _api = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ CRUD

  Future<void> saveTodo(Todo todo) async {
    // Veralteter Editor-Stand: Wurde das ToDo zwischenzeitlich durch einen
    // Pull aktualisiert (anderes Objekt, jüngerer Zeitstempel), die dortige
    // Fassung als Konfliktkopie retten statt sie stillschweigend zu
    // überschreiben.
    final current = _store!.byId(todo.id);
    if (current != null &&
        !identical(current, todo) &&
        current.updatedAt.isAfter(todo.updatedAt)) {
      await _store!.upsert(conflictCopyOf(current));
    }
    await _store!.upsert(todo);
    await notifications.scheduleForTodo(todo);
    notifyListeners();
    unawaited(syncNow(silent: true));
  }

  Future<void> deleteTodo(Todo todo) async {
    await notifications.cancelForTodo(todo);
    await _store!.remove(todo.id);
    notifyListeners();
    unawaited(syncNow(silent: true));
  }

  /// Erledigt-Umschalter inkl. Wiederholungslogik: beim Abschließen eines
  /// wiederkehrenden ToDos wird automatisch die Folgeinstanz angelegt.
  Future<void> setDone(Todo todo, bool done) async {
    todo.status = done ? TodoStatus.done : TodoStatus.open;
    todo.completedAt = done ? DateTime.now() : null;
    await _store!.upsert(todo);
    await notifications.scheduleForTodo(todo);

    if (done) {
      final next = createNextInstance(todo);
      if (next != null) {
        // Wiederholung wandert zur Folgeinstanz.
        todo.recurrence = null;
        await _store!.upsert(todo);
        await _store!.upsert(next);
        await notifications.scheduleForTodo(next);
      }
    }
    notifyListeners();
    unawaited(syncNow(silent: true));
  }

  // ------------------------------------------------------------ Sync

  Future<void> syncNow({bool silent = false}) async {
    if (syncing || _sync == null) return;
    syncing = true;
    if (!silent) notifyListeners();
    try {
      lastSyncResult = await _sync!.sync();
      syncError = null;
      // Nach Pull ggf. neue/geänderte Erinnerungen einplanen.
      for (final todo in todos) {
        await notifications.scheduleForTodo(todo);
      }
    } on GithubApiException catch (e) {
      syncError = e.isUnauthorized
          ? 'GitHub-Token ungültig oder abgelaufen.'
          : 'Sync fehlgeschlagen: ${e.message}';
    } catch (e) {
      syncError = 'Sync fehlgeschlagen: $e';
    } finally {
      syncing = false;
      notifyListeners();
      // Während des Syncs aufgelaufene Änderungen zeitnah nachschieben.
      if (syncError == null && pendingCount > 0) {
        Timer(const Duration(seconds: 2), () => syncNow(silent: true));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}

class OnboardingException implements Exception {
  const OnboardingException(this.message);
  final String message;
  @override
  String toString() => message;
}

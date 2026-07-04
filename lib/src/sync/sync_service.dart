import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../crypto/crypto_service.dart';
import '../models/todo.dart';
import '../storage/local_store.dart';
import 'github_api.dart';

const String kTodoDir = 'todos';
const String kIndexPath = 'index.enc';
const String kMetaPath = 'meta.json';
const String _commitMessage = 'sync';

class SyncResult {
  int pushed = 0;
  int pulled = 0;
  int conflicts = 0;

  /// Beim Pull übersprungene, nicht entschlüsselbare Dateien.
  int skipped = 0;

  @override
  String toString() =>
      'gesendet: $pushed, empfangen: $pulled, Konflikte: $conflicts'
      '${skipped > 0 ? ', übersprungen: $skipped' : ''}';
}

/// Synchronisiert den lokalen Store mit dem GitHub-Repo.
///
/// Strategie (Einzelnutzer): "Last write wins" über updated_at. Die
/// unterlegene Fassung wird als Kopie `<Titel> (Konflikt)` aufgehoben,
/// es geht also nie etwas verloren.
class SyncService {
  SyncService({
    required this.store,
    required this.api,
    required this.crypto,
    required this.key,
  });

  final LocalStore store;
  final GithubApi api;
  final CryptoService crypto;
  final SecretKey key;

  String _todoPath(String id) => '$kTodoDir/$id.enc';

  Future<SyncResult> sync() async {
    final result = SyncResult();
    await _push(result);
    await _pull(result);
    await _updateRemoteIndex();
    store.lastSync = DateTime.now();
    await store.saveState();
    return result;
  }

  // ---------------------------------------------------------------- Push

  Future<void> _push(SyncResult result) async {
    for (final op in List.of(store.pending)) {
      if (op.isDelete) {
        await _pushDelete(op, result);
      } else {
        await _pushUpsert(op, result);
      }
    }
  }

  Future<void> _pushUpsert(PendingOp op, SyncResult result) async {
    final todo = store.byId(op.id);
    if (todo == null) return; // inzwischen gelöscht; Delete-Op folgt
    final bytes = await crypto.encryptJson(todo.toJson(), key);
    final knownSha = store.remoteShas[op.id];
    try {
      final newSha = await api.putFile(_todoPath(op.id), bytes, _commitMessage,
          sha: knownSha);
      store.markSynced(op, newSha: newSha);
      result.pushed++;
    } on GithubApiException catch (e) {
      if (!e.isConflict) rethrow;
      await _resolveUpsertConflict(op, todo, bytes, result);
    }
  }

  /// SHA-Konflikt: Remote-Datei wurde von einem anderen Gerät geändert.
  Future<void> _resolveUpsertConflict(
      PendingOp op, Todo local, List<int> bytes, SyncResult result) async {
    final remoteFile = await api.getFile(_todoPath(op.id));
    if (remoteFile == null) {
      // Remote gelöscht, lokal geändert: lokale Fassung neu anlegen (LWW
      // zugunsten der Änderung — Löschung ohne Datenverlust umkehrbar).
      final newSha =
          await api.putFile(_todoPath(op.id), bytes, _commitMessage);
      store.markSynced(op, newSha: newSha);
      result.pushed++;
      return;
    }
    final remoteTodo = Todo.fromJson(await crypto.decryptJson(
        remoteFile.content!, key) as Map<String, dynamic>);

    // Beide Fassungen bleiben erhalten: die unterlegene wird als
    // Konfliktkopie gerettet — egal, welche Seite gewinnt.
    result.conflicts++;
    if (remoteTodo.updatedAt.isAfter(local.updatedAt)) {
      // Remote gewinnt: lokale Fassung als Kopie aufheben, Remote übernehmen.
      final conflictCopy = conflictCopyOf(local);
      store.remoteShas[op.id] = remoteFile.sha;
      await store.upsert(remoteTodo, fromRemote: true);
      store.markSynced(op);
      await _pushNewCopy(conflictCopy, result);
    } else {
      // Lokal gewinnt: überschriebene Remote-Fassung als Kopie aufheben.
      final conflictCopy = conflictCopyOf(remoteTodo);
      final newSha = await api.putFile(_todoPath(op.id), bytes, _commitMessage,
          sha: remoteFile.sha);
      store.markSynced(op, newSha: newSha);
      result.pushed++;
      await _pushNewCopy(conflictCopy, result);
    }
  }

  Future<void> _pushNewCopy(Todo copy, SyncResult result) async {
    await store.upsert(copy); // landet als neue Datei in der Queue
    final copyOp = store.pending.where((p) => p.id == copy.id).firstOrNull;
    if (copyOp != null) await _pushUpsert(copyOp, result);
  }

  Future<void> _pushDelete(PendingOp op, SyncResult result) async {
    final sha = store.remoteShas[op.id];
    if (sha == null) {
      store.markSynced(op);
      return;
    }
    try {
      await api.deleteFile(_todoPath(op.id), sha, _commitMessage);
      store.markSynced(op);
      result.pushed++;
    } on GithubApiException catch (e) {
      if (!e.isConflict) rethrow;
      // Remote zwischenzeitlich geändert: Änderung schlägt Löschung.
      final remoteFile = await api.getFile(_todoPath(op.id));
      if (remoteFile == null) {
        store.markSynced(op);
        return;
      }
      final remoteTodo = Todo.fromJson(await crypto.decryptJson(
          remoteFile.content!, key) as Map<String, dynamic>);
      store.remoteShas[op.id] = remoteFile.sha;
      await store.upsert(remoteTodo, fromRemote: true);
      store.markSynced(op);
      result.conflicts++;
    }
  }

  // ---------------------------------------------------------------- Pull

  Future<void> _pull(SyncResult result) async {
    final listing = await api.listDir(kTodoDir);

    for (final entry in listing.entries) {
      if (!entry.key.endsWith('.enc')) continue;
      final id = entry.key.substring(0, entry.key.length - 4);
      if (store.hasPendingFor(id)) continue; // lokale Änderung hat Vorrang
      if (store.remoteShas[id] == entry.value) continue; // unverändert
      final file = await api.getFile(_todoPath(id));
      if (file == null) continue;
      // Eine einzelne defekte Datei darf nicht den gesamten Sync blockieren:
      // überspringen und beim nächsten Sync erneut versuchen.
      try {
        final todo = Todo.fromJson(await crypto.decryptJson(file.content!, key)
            as Map<String, dynamic>);
        store.remoteShas[id] = file.sha;
        await store.upsert(todo, fromRemote: true);
        result.pulled++;
      } on DecryptionFailedException {
        result.skipped++;
      }
    }

    // Remote gelöschte ToDos lokal entfernen. Das Verzeichnis-Listing kann
    // veraltet sein — vor dem Löschen die Datei einzeln verifizieren.
    final remoteIds = listing.keys
        .where((n) => n.endsWith('.enc'))
        .map((n) => n.substring(0, n.length - 4))
        .toSet();
    final locallyKnown = List.of(store.remoteShas.keys);
    for (final id in locallyKnown) {
      if (remoteIds.contains(id) || store.hasPendingFor(id)) continue;
      final still = await api.getFile(_todoPath(id));
      if (still != null) {
        // Datei existiert doch (Listing war veraltet) — ggf. übernehmen.
        if (still.sha != store.remoteShas[id]) {
          final todo = Todo.fromJson(await crypto.decryptJson(
              still.content!, key) as Map<String, dynamic>);
          store.remoteShas[id] = still.sha;
          await store.upsert(todo, fromRemote: true);
        }
        continue;
      }
      await store.remove(id, fromRemote: true);
      result.pulled++;
    }
  }

  // ---------------------------------------------------------------- Index

  Future<void> _updateRemoteIndex() async {
    final entries =
        store.todos.map((t) => IndexEntry.fromTodo(t).toJson()).toList();
    final bytes = await crypto.encryptJson({'entries': entries}, key);
    try {
      store.remoteIndexSha = await api.putFile(
          kIndexPath, bytes, _commitMessage,
          sha: store.remoteIndexSha);
    } on GithubApiException catch (e) {
      if (!e.isConflict) rethrow;
      final current = await api.getFile(kIndexPath);
      store.remoteIndexSha = await api.putFile(
          kIndexPath, bytes, _commitMessage,
          sha: current?.sha);
    }
  }

  // ------------------------------------------------------------ Einrichtung

  /// Liest die KDF-Parameter aus meta.json; null, wenn Repo nicht
  /// initialisiert ist.
  static Future<CryptoParams?> fetchMeta(GithubApi api) async {
    final file = await api.getFile(kMetaPath);
    if (file == null) return null;
    return CryptoParams.fromJson(
        jsonDecode(utf8.decode(file.content!)) as Map<String, dynamic>);
  }

  /// Initialisiert ein leeres Daten-Repo (meta.json + leerer Index).
  static Future<void> initializeRemote(
      GithubApi api, CryptoService crypto, SecretKey key, CryptoParams params) async {
    await api.putFile(kMetaPath,
        utf8.encode(jsonEncode(params.toJson())), 'init: meta');
    await api.putFile(kIndexPath,
        await crypto.encryptJson({'entries': []}, key), 'init: index');
  }

  /// Verifiziert die Passphrase gegen den Remote-Index.
  static Future<bool> verifyKey(
      GithubApi api, CryptoService crypto, SecretKey key) async {
    final index = await api.getFile(kIndexPath);
    if (index == null) return true; // nichts zum Prüfen — frisches Repo
    try {
      await crypto.decryptJson(index.content!, key);
      return true;
    } on DecryptionFailedException {
      return false;
    }
  }
}

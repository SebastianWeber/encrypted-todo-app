import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../crypto/crypto_service.dart';
import '../models/todo.dart';

/// Ausstehende, noch nicht synchronisierte Änderung.
class PendingOp {
  PendingOp({required this.id, required this.isDelete, DateTime? at})
      : at = at ?? DateTime.now();

  final String id;
  final bool isDelete;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'id': id, 'delete': isDelete, 'at': at.toIso8601String()};

  factory PendingOp.fromJson(Map<String, dynamic> json) => PendingOp(
        id: json['id'] as String,
        isDelete: json['delete'] as bool? ?? false,
        at: DateTime.parse(json['at'] as String),
      );
}

/// Lokaler Store: Quelle der Wahrheit der App (Offline-First).
///
/// Ablage auf Platte ausschließlich verschlüsselt, im selben Dokumentformat
/// wie im GitHub-Repo:
///   `<base>/todos/<id>.enc` — ein Dokument pro ToDo
///   `<base>/state.enc`      — Sync-Zustand (Remote-SHAs, Queue, letzter Sync)
class LocalStore {
  LocalStore({
    required this.baseDir,
    required this.crypto,
    required this.key,
  });

  final String baseDir;
  final CryptoService crypto;
  final SecretKey key;

  final Map<String, Todo> _todos = {};
  final Map<String, String> remoteShas = {};
  final List<PendingOp> _pending = [];
  String? remoteIndexSha;
  DateTime? lastSync;

  List<Todo> get todos => _todos.values.toList();
  Todo? byId(String id) => _todos[id];
  List<PendingOp> get pending => List.unmodifiable(_pending);
  int get pendingCount => _pending.length;
  bool hasPendingFor(String id) => _pending.any((op) => op.id == id);

  Directory get _todoDir => Directory('$baseDir/todos');
  File get _stateFile => File('$baseDir/state.enc');
  File _todoFile(String id) => File('$baseDir/todos/$id.enc');

  Future<void> init() async {
    await _todoDir.create(recursive: true);
    if (await _stateFile.exists()) {
      final state = await crypto.decryptJson(
          await _stateFile.readAsBytes(), key) as Map<String, dynamic>;
      remoteShas.addAll(
          (state['remote_shas'] as Map<String, dynamic>).cast<String, String>());
      _pending.addAll((state['pending'] as List)
          .map((p) => PendingOp.fromJson(p as Map<String, dynamic>)));
      remoteIndexSha = state['remote_index_sha'] as String?;
      final ls = state['last_sync'] as String?;
      lastSync = ls == null ? null : DateTime.parse(ls);
    }
    await for (final entity in _todoDir.list()) {
      if (entity is! File || !entity.path.endsWith('.enc')) continue;
      try {
        final json = await crypto.decryptJson(await entity.readAsBytes(), key);
        final todo = Todo.fromJson(json as Map<String, dynamic>);
        _todos[todo.id] = todo;
      } on DecryptionFailedException {
        // Beschädigte Datei überspringen statt die ganze App zu blockieren.
        continue;
      }
    }
  }

  /// Speichert ein ToDo lokal. [fromRemote]=true beim Übernehmen von
  /// Remote-Änderungen (erzeugt keinen Queue-Eintrag).
  Future<void> upsert(Todo todo, {bool fromRemote = false}) async {
    if (!fromRemote) todo.updatedAt = DateTime.now();
    _todos[todo.id] = todo;
    await _todoFile(todo.id).writeAsBytes(
        await crypto.encryptJson(todo.toJson(), key));
    if (!fromRemote) _enqueue(PendingOp(id: todo.id, isDelete: false));
    await saveState();
  }

  Future<void> remove(String id, {bool fromRemote = false}) async {
    _todos.remove(id);
    final f = _todoFile(id);
    if (await f.exists()) await f.delete();
    if (fromRemote) {
      remoteShas.remove(id);
      _pending.removeWhere((op) => op.id == id);
    } else {
      _enqueue(PendingOp(id: id, isDelete: true));
    }
    await saveState();
  }

  /// Pro ToDo maximal ein Queue-Eintrag; der jüngste gewinnt.
  void _enqueue(PendingOp op) {
    _pending.removeWhere((p) => p.id == op.id);
    // Löschung eines noch nie synchronisierten ToDos: nichts zu tun.
    if (op.isDelete && !remoteShas.containsKey(op.id)) return;
    _pending.add(op);
  }

  void markSynced(PendingOp op, {String? newSha}) {
    _pending.remove(op);
    if (op.isDelete || newSha == null) {
      if (op.isDelete) remoteShas.remove(op.id);
    } else {
      remoteShas[op.id] = newSha;
    }
  }

  Future<void> saveState() async {
    await _stateFile.writeAsBytes(await crypto.encryptJson({
      'remote_shas': remoteShas,
      'pending': _pending.map((p) => p.toJson()).toList(),
      'remote_index_sha': remoteIndexSha,
      'last_sync': lastSync?.toIso8601String(),
    }, key));
  }

  /// Löscht alle lokalen Daten (z. B. bei Abmelden/Neueinrichtung).
  Future<void> wipe() async {
    final dir = Directory(baseDir);
    if (await dir.exists()) await dir.delete(recursive: true);
    _todos.clear();
    remoteShas.clear();
    _pending.clear();
    remoteIndexSha = null;
    lastSync = null;
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:encrypted_todo_app/src/crypto/crypto_service.dart';
import 'package:encrypted_todo_app/src/models/todo.dart';
import 'package:encrypted_todo_app/src/storage/local_store.dart';
import 'package:encrypted_todo_app/src/sync/github_api.dart';
import 'package:encrypted_todo_app/src/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-Memory-Nachbildung der GitHub-Contents-API inkl. SHA-Konflikten.
class FakeGithubApi implements GithubApi {
  @override
  final GithubConfig config =
      const GithubConfig(owner: 'test', repo: 'test', token: 'test');

  final Map<String, Uint8List> files = {};
  final Map<String, int> _revs = {};

  String _sha(String path) => '$path@${_revs[path]}';

  @override
  Future<void> testConnection() async {}

  @override
  Future<Map<String, String>> listDir(String path) async => {
        for (final p in files.keys)
          if (p.startsWith('$path/') && !p.substring(path.length + 1).contains('/'))
            p.substring(path.length + 1): _sha(p),
      };

  @override
  Future<RemoteFile?> getFile(String path) async {
    final content = files[path];
    if (content == null) return null;
    return RemoteFile(path: path, sha: _sha(path), content: content);
  }

  @override
  Future<String> putFile(String path, List<int> content, String message,
      {String? sha}) async {
    final exists = files.containsKey(path);
    if (exists && sha != _sha(path)) {
      throw const GithubApiException(409, 'sha mismatch');
    }
    if (!exists && sha != null) {
      throw const GithubApiException(422, 'sha given for new file');
    }
    files[path] = Uint8List.fromList(content);
    _revs[path] = (_revs[path] ?? 0) + 1;
    return _sha(path);
  }

  @override
  Future<void> deleteFile(String path, String sha, String message) async {
    if (!files.containsKey(path)) return;
    if (sha != _sha(path)) throw const GithubApiException(409, 'sha mismatch');
    files.remove(path);
    _revs.remove(path);
  }
}

void main() {
  final crypto = CryptoService();
  late SecretKey key;
  late FakeGithubApi api;
  final tempDirs = <Directory>[];

  Future<(LocalStore, SyncService)> makeDevice() async {
    final dir = await Directory.systemTemp.createTemp('todo_sync_test');
    tempDirs.add(dir);
    final store = LocalStore(baseDir: dir.path, crypto: crypto, key: key);
    await store.init();
    return (store, SyncService(store: store, api: api, crypto: crypto, key: key));
  }

  setUpAll(() async {
    key = await crypto.deriveKey(
        'test-passphrase',
        CryptoParams(
            salt: base64Encode(List.generate(16, (i) => i)),
            memoryKiB: 256,
            iterations: 1,
            parallelism: 1));
  });

  setUp(() => api = FakeGithubApi());

  tearDownAll(() async {
    for (final d in tempDirs) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('Push: neues ToDo landet verschlüsselt im Repo', () async {
    final (store, sync) = await makeDevice();
    await store.upsert(Todo(title: 'Zahnarzttermin'));
    expect(store.pendingCount, 1);

    final result = await sync.sync();

    expect(result.pushed, 1);
    expect(store.pendingCount, 0);
    expect(api.files.keys.where((p) => p.startsWith('todos/')), hasLength(1));
    expect(api.files.containsKey('index.enc'), true);
    // Inhalt ist nicht im Klartext ablesbar.
    final raw = utf8.decode(api.files.values.first, allowMalformed: true);
    expect(raw, isNot(contains('Zahnarzttermin')));
  });

  test('Pull: zweites Gerät empfängt ToDos und Löschungen', () async {
    final (storeA, syncA) = await makeDevice();
    final todo = Todo(title: 'Von Gerät A');
    await storeA.upsert(todo);
    await syncA.sync();

    final (storeB, syncB) = await makeDevice();
    final pullResult = await syncB.sync();
    expect(pullResult.pulled, 1);
    expect(storeB.todos.single.title, 'Von Gerät A');
    expect(storeB.todos.single.id, todo.id);

    // Löschung auf A kommt bei B an.
    await storeA.remove(todo.id);
    await syncA.sync();
    await syncB.sync();
    expect(storeB.todos, isEmpty);
  });

  test('Konflikt: jüngere Änderung gewinnt, ältere bleibt als Kopie erhalten',
      () async {
    final (storeA, syncA) = await makeDevice();
    final todo = Todo(title: 'Bericht schreiben');
    await storeA.upsert(todo);
    await syncA.sync();

    final (storeB, syncB) = await makeDevice();
    await syncB.sync();

    // A ändert zuerst (älterer Zeitstempel), synct aber nicht.
    final localA = storeA.byId(todo.id)!..title = 'Bericht schreiben (Alt)';
    await storeA.upsert(localA);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // B ändert später und synct zuerst.
    final localB = storeB.byId(todo.id)!..title = 'Bericht schreiben (Neu)';
    await storeB.upsert(localB);
    await syncB.sync();

    // A synct danach: Remote (B) ist jünger und gewinnt.
    final result = await syncA.sync();

    expect(result.conflicts, 1);
    expect(storeA.byId(todo.id)!.title, 'Bericht schreiben (Neu)');
    final conflictCopies = storeA.todos
        .where((t) => t.title.contains('(Konflikt)'))
        .toList();
    expect(conflictCopies, hasLength(1));
    expect(conflictCopies.single.title, contains('(Alt)'));
    // Konfliktkopie wurde auch hochgeladen (2 Dateien im Repo).
    expect(api.files.keys.where((p) => p.startsWith('todos/')), hasLength(2));

    // B sieht die Konfliktkopie nach dem nächsten Sync ebenfalls.
    await syncB.sync();
    expect(storeB.todos, hasLength(2));
  });

  test('Konflikt: Löschung verliert gegen Änderung', () async {
    final (storeA, syncA) = await makeDevice();
    final todo = Todo(title: 'Diskussionspunkt');
    await storeA.upsert(todo);
    await syncA.sync();

    final (storeB, syncB) = await makeDevice();
    await syncB.sync();

    // A löscht (ohne Sync), B ändert und synct.
    await storeA.remove(todo.id);
    final localB = storeB.byId(todo.id)!..title = 'Doch behalten';
    await storeB.upsert(localB);
    await syncB.sync();

    // A synct: Löschung trifft auf geänderte Datei -> Änderung gewinnt.
    final result = await syncA.sync();
    expect(result.conflicts, 1);
    expect(storeA.byId(todo.id)!.title, 'Doch behalten');
  });

  test('Offline-Persistenz: Queue überlebt Neustart des Stores', () async {
    final dir = await Directory.systemTemp.createTemp('todo_sync_test');
    tempDirs.add(dir);
    final store1 = LocalStore(baseDir: dir.path, crypto: crypto, key: key);
    await store1.init();
    await store1.upsert(Todo(title: 'Offline erstellt'));
    expect(store1.pendingCount, 1);

    // "Neustart": neuer Store auf demselben Verzeichnis.
    final store2 = LocalStore(baseDir: dir.path, crypto: crypto, key: key);
    await store2.init();
    expect(store2.pendingCount, 1);
    expect(store2.todos.single.title, 'Offline erstellt');

    final sync2 = SyncService(store: store2, api: api, crypto: crypto, key: key);
    final result = await sync2.sync();
    expect(result.pushed, 1);
    expect(store2.pendingCount, 0);
  });
}

// Diagnose: führt einen vollständigen Sync gegen ein echtes Daten-Repo aus
// (frischer, temporärer lokaler Store) und meldet Ergebnis oder Exception.
//
// Env: TODO_PASSPHRASE, GH_OWNER, GH_REPO, GH_TOKEN [, GH_BRANCH]
import 'dart:io';

import 'package:encrypted_todo_app/src/crypto/crypto_service.dart';
import 'package:encrypted_todo_app/src/storage/local_store.dart';
import 'package:encrypted_todo_app/src/sync/github_api.dart';
import 'package:encrypted_todo_app/src/sync/sync_service.dart';

Future<void> main() async {
  final env = Platform.environment;
  final api = GithubApi(GithubConfig(
    owner: env['GH_OWNER']!,
    repo: env['GH_REPO']!,
    branch: env['GH_BRANCH'] ?? 'main',
    token: env['GH_TOKEN']!,
  ));
  final crypto = CryptoService();

  final params = await SyncService.fetchMeta(api);
  if (params == null) {
    stdout.writeln('FEHLER: meta.json nicht gefunden');
    exit(1);
  }
  final key = await crypto.deriveKey(env['TODO_PASSPHRASE']!, params);

  final dir = await Directory.systemTemp.createTemp('sync_probe');
  final store = LocalStore(baseDir: dir.path, crypto: crypto, key: key);
  await store.init();
  final sync = SyncService(store: store, api: api, crypto: crypto, key: key);

  try {
    final r1 = await sync.sync();
    stdout.writeln('Sync 1 OK: $r1  (lokal: ${store.todos.length} ToDos)');
    final r2 = await sync.sync();
    stdout.writeln('Sync 2 OK: $r2');
  } catch (e, st) {
    stdout.writeln('SYNC-EXCEPTION: $e');
    stdout.writeln(st.toString().split('\n').take(8).join('\n'));
    exit(2);
  } finally {
    await dir.delete(recursive: true);
  }
}

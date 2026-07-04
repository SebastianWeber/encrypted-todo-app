// Diagnose: lädt jede Datei einzeln über die Contents API und prüft
// Entschlüsselung; vergleicht Bytegrößen mit Erwartung.
import 'dart:io';

import 'package:encrypted_todo_app/src/crypto/crypto_service.dart';
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
  final params = (await SyncService.fetchMeta(api))!;
  final key = await crypto.deriveKey(env['TODO_PASSPHRASE']!, params);

  final listing = await api.listDir('todos');
  stdout.writeln('${listing.length} Dateien im Listing');
  for (final name in listing.keys) {
    final f = await api.getFile('todos/$name');
    if (f == null) {
      stdout.writeln('$name  GETFILE=NULL');
      continue;
    }
    final n = f.content!.length;
    String status;
    try {
      await crypto.decryptJson(f.content!, key);
      status = 'OK';
    } catch (e) {
      status = 'FEHLER: $e (erste Bytes: ${f.content!.take(8).toList()})';
    }
    stdout.writeln('$name  $n Bytes  $status');
  }
}

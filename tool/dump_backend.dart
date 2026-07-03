// Diagnose-Werkzeug: entschlüsselt ein Daten-Repo und listet Index +
// Dokumente kompakt auf.
//
//   dart run tool/dump_backend.dart <repo-pfad>
//
// Die Passphrase wird aus der Umgebungsvariable TODO_PASSPHRASE gelesen,
// damit sie nicht in Shell-History oder Prozessliste auftaucht.
import 'dart:convert';
import 'dart:io';

import 'package:encrypted_todo_app/src/crypto/crypto_service.dart';

Future<void> main(List<String> args) async {
  final repo = args[0];
  final pass = Platform.environment['TODO_PASSPHRASE']!;
  final crypto = CryptoService();
  final params = CryptoParams.fromJson(
      jsonDecode(File('$repo/meta.json').readAsStringSync())
          as Map<String, dynamic>);
  final key = await crypto.deriveKey(pass, params);

  String row(Map j) =>
      '${(j['id'] as String).substring(0, 8)}  ${j['status']}  '
      'due=${j['due'] ?? '-'}  upd=${j['updated_at']}  ${j['title']}';

  stdout.writeln('== INDEX ==');
  final idx = await crypto.decryptJson(
      File('$repo/index.enc').readAsBytesSync(), key) as Map;
  for (final e in idx['entries'] as List) {
    stdout.writeln(row(e as Map));
  }

  stdout.writeln('== DOKUMENTE ==');
  final files = Directory('$repo/todos').listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final j =
        await crypto.decryptJson(f.readAsBytesSync(), key) as Map;
    stdout.writeln(row(j));
    final desc = j['description'] as String? ?? '';
    final subs = (j['subtasks'] as List?) ?? [];
    if (desc.isNotEmpty) {
      stdout.writeln('    beschr: ${desc.replaceAll('\n', ' | ')}');
    }
    if (subs.isNotEmpty) {
      stdout.writeln(
          '    teilschritte: ${subs.map((s) => '${s['done'] == true ? '[x]' : '[ ]'}${s['text']}').join(' ')}');
    }
    if (j['recurrence'] != null) {
      stdout.writeln('    wiederholung: ${jsonEncode(j['recurrence'])}');
    }
  }
}

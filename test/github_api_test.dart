import 'dart:convert';

import 'package:encrypted_todo_app/src/sync/github_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('getFile holt Bytes über die Blobs-API, nicht das content-Feld',
      () async {
    // Regression: Die Contents-API unterzieht Blobs einer Zeichensatz-
    // Erkennung und lieferte Ciphertext, der zufällig wie UTF-16 aussah,
    // nach UTF-8 transkodiert (und damit unbrauchbar) aus. Die Blobs-API
    // liefert byte-genau.
    final trueBytes = [1, 16, 2, 80, 66, 159, 81, 38];
    // So sah der Schaden real aus: als UTF-16BE gedeutet, UTF-8-kodiert.
    final transcoded = utf8.encode('Đɐ䊟');

    final client = MockClient((req) async {
      if (req.url.path.contains('/git/blobs/blobsha123')) {
        return http.Response(
            jsonEncode({
              'content': base64Encode(trueBytes),
              'encoding': 'base64',
            }),
            200);
      }
      if (req.url.path.contains('/contents/todos/x.enc')) {
        return http.Response(
            jsonEncode({
              'sha': 'blobsha123',
              'size': trueBytes.length,
              'content': base64Encode(transcoded),
              'encoding': 'base64',
            }),
            200);
      }
      return http.Response('unerwarteter Aufruf: ${req.url}', 500);
    });

    final api = GithubApi(
      const GithubConfig(owner: 'o', repo: 'r', token: 't'),
      client: client,
    );

    final file = await api.getFile('todos/x.enc');

    expect(file, isNotNull);
    expect(file!.sha, 'blobsha123');
    expect(file.content, trueBytes);
  });
}

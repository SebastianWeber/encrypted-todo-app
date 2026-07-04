import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GithubConfig {
  const GithubConfig({
    required this.owner,
    required this.repo,
    this.branch = 'main',
    required this.token,
  });

  final String owner;
  final String repo;
  final String branch;
  final String token;
}

class RemoteFile {
  const RemoteFile({required this.path, required this.sha, this.content});
  final String path;
  final String sha;
  final Uint8List? content;
}

class GithubApiException implements Exception {
  const GithubApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  /// SHA-Konflikt: Datei wurde zwischenzeitlich remote geändert.
  bool get isConflict => statusCode == 409 || statusCode == 422;

  @override
  String toString() => 'GitHub-API-Fehler $statusCode: $message';
}

/// Dünner Client für die GitHub-Contents-API — genügt als komplettes
/// "Datenbank-Protokoll": lesen, schreiben, löschen, auflisten.
class GithubApi {
  GithubApi(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final GithubConfig config;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${config.token}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Uri _contentsUri(String path, [Map<String, String>? query]) => Uri.https(
        'api.github.com',
        '/repos/${config.owner}/${config.repo}/contents/$path',
        query,
      );

  /// Prüft Token und Repo-Zugriff; wirft bei Fehlern.
  Future<void> testConnection() async {
    final res = await _client.get(
      Uri.https('api.github.com', '/repos/${config.owner}/${config.repo}'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw GithubApiException(res.statusCode, _errorMessage(res));
    }
  }

  /// Listet Dateien eines Verzeichnisses (Name -> SHA). Leer bei 404.
  Future<Map<String, String>> listDir(String path) async {
    final res = await _client.get(
        _contentsUri(path, {'ref': config.branch}),
        headers: _headers);
    if (res.statusCode == 404) return {};
    if (res.statusCode != 200) {
      throw GithubApiException(res.statusCode, _errorMessage(res));
    }
    final entries = jsonDecode(res.body) as List;
    return {
      for (final e in entries.cast<Map<String, dynamic>>())
        if (e['type'] == 'file') e['name'] as String: e['sha'] as String,
    };
  }

  /// Lädt eine Datei; null bei 404.
  ///
  /// Der Inhalt wird über die Git-Blobs-API geholt, NICHT aus dem
  /// content-Feld der Contents-API: Letztere unterzieht Dateien einer
  /// Zeichensatz-Erkennung und transkodiert vermeintliches UTF-16 nach
  /// UTF-8 — zufällige Ciphertext-Bytes können so verfälscht ankommen.
  /// Die Blobs-API liefert das Blob byte-genau.
  Future<RemoteFile?> getFile(String path) async {
    final res = await _client.get(
        _contentsUri(path, {'ref': config.branch}),
        headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw GithubApiException(res.statusCode, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final sha = json['sha'] as String;
    return RemoteFile(path: path, sha: sha, content: await _getBlob(sha));
  }

  Future<Uint8List> _getBlob(String sha) async {
    final res = await _client.get(
      Uri.https('api.github.com',
          '/repos/${config.owner}/${config.repo}/git/blobs/$sha'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw GithubApiException(res.statusCode, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return base64Decode(
        (json['content'] as String? ?? '').replaceAll(RegExp(r'\s'), ''));
  }

  /// Legt eine Datei an oder aktualisiert sie. [sha] ist beim Aktualisieren
  /// Pflicht (optimistische Sperre). Liefert den neuen Blob-SHA.
  Future<String> putFile(String path, List<int> content, String message,
      {String? sha}) async {
    final res = await _client.put(
      _contentsUri(path),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'content': base64Encode(content),
        'branch': config.branch,
        'sha': ?sha,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw GithubApiException(res.statusCode, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['content'] as Map<String, dynamic>)['sha'] as String;
  }

  Future<void> deleteFile(String path, String sha, String message) async {
    final res = await _client.delete(
      _contentsUri(path),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'sha': sha,
        'branch': config.branch,
      }),
    );
    if (res.statusCode == 404) return; // schon weg — Ziel erreicht
    if (res.statusCode != 200) {
      throw GithubApiException(res.statusCode, _errorMessage(res));
    }
  }

  String _errorMessage(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map<String, dynamic>)['message']
              as String? ??
          res.body;
    } catch (_) {
      return res.body;
    }
  }
}

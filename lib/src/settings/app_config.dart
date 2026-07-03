import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/crypto_service.dart';

/// Vollständige App-Konfiguration; sicher abgelegt via flutter_secure_storage
/// (Windows: DPAPI/Credential Manager, Android: Keystore).
class AppConfig {
  AppConfig({
    required this.owner,
    required this.repo,
    this.branch = 'main',
    required this.token,
    required this.masterKeyB64,
    required this.cryptoParams,
    this.rememberKey = true,
  });

  final String owner;
  final String repo;
  final String branch;
  final String token;

  /// Abgeleiteter Master-Key (Base64). Leer, wenn rememberKey=false —
  /// dann wird die Passphrase bei jedem Start abgefragt.
  final String masterKeyB64;
  final CryptoParams cryptoParams;
  final bool rememberKey;
}

class AppConfigStore {
  AppConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kOwner = 'gh_owner';
  static const _kRepo = 'gh_repo';
  static const _kBranch = 'gh_branch';
  static const _kToken = 'gh_token';
  static const _kMasterKey = 'master_key';
  static const _kParams = 'crypto_params';
  static const _kRememberKey = 'remember_key';

  Future<AppConfig?> load() async {
    final owner = await _storage.read(key: _kOwner);
    final repo = await _storage.read(key: _kRepo);
    final token = await _storage.read(key: _kToken);
    final params = await _storage.read(key: _kParams);
    if (owner == null || repo == null || token == null || params == null) {
      return null;
    }
    return AppConfig(
      owner: owner,
      repo: repo,
      branch: await _storage.read(key: _kBranch) ?? 'main',
      token: token,
      masterKeyB64: await _storage.read(key: _kMasterKey) ?? '',
      cryptoParams: CryptoParams.fromJson(
          jsonDecode(params) as Map<String, dynamic>),
      rememberKey: (await _storage.read(key: _kRememberKey)) != 'false',
    );
  }

  Future<void> save(AppConfig config) async {
    await _storage.write(key: _kOwner, value: config.owner);
    await _storage.write(key: _kRepo, value: config.repo);
    await _storage.write(key: _kBranch, value: config.branch);
    await _storage.write(key: _kToken, value: config.token);
    await _storage.write(
        key: _kMasterKey,
        value: config.rememberKey ? config.masterKeyB64 : '');
    await _storage.write(
        key: _kParams, value: jsonEncode(config.cryptoParams.toJson()));
    await _storage.write(
        key: _kRememberKey, value: config.rememberKey.toString());
  }

  Future<void> clear() => _storage.deleteAll();
}

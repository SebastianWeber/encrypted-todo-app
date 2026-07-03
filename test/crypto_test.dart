import 'dart:convert';

import 'package:encrypted_todo_app/src/crypto/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kleine KDF-Parameter, damit die Tests schnell laufen.
CryptoParams testParams() => CryptoParams(
      salt: base64Encode(List.generate(16, (i) => i)),
      memoryKiB: 256,
      iterations: 1,
      parallelism: 1,
    );

void main() {
  final crypto = CryptoService();

  test('Verschlüsselung: Roundtrip liefert Klartext zurück', () async {
    final key = await crypto.deriveKey('geheime passphrase', testParams());
    final data = {'title': 'Einkaufen', 'umlaute': 'äöüß', 'n': 42};

    final encrypted = await crypto.encryptJson(data, key);
    final decrypted = await crypto.decryptJson(encrypted, key);

    expect(decrypted, data);
    // Ciphertext darf den Klartext nicht enthalten.
    expect(utf8.decode(encrypted, allowMalformed: true),
        isNot(contains('Einkaufen')));
  });

  test('Gleicher Klartext ergibt unterschiedliche Ciphertexte (Nonce)',
      () async {
    final key = await crypto.deriveKey('pass1pass1', testParams());
    final a = await crypto.encryptJson({'x': 1}, key);
    final b = await crypto.encryptJson({'x': 1}, key);
    expect(base64Encode(a), isNot(base64Encode(b)));
  });

  test('Falsche Passphrase schlägt fehl', () async {
    final params = testParams();
    final key = await crypto.deriveKey('richtige passphrase', params);
    final wrongKey = await crypto.deriveKey('falsche passphrase', params);

    final encrypted = await crypto.encryptJson({'geheim': true}, key);

    expect(() => crypto.decryptJson(encrypted, wrongKey),
        throwsA(isA<DecryptionFailedException>()));
  });

  test('Manipulierte Daten schlagen fehl (Authentizität)', () async {
    final key = await crypto.deriveKey('passphrase123', testParams());
    final encrypted = await crypto.encryptJson({'a': 1}, key);
    encrypted[encrypted.length ~/ 2] ^= 0xFF;

    expect(() => crypto.decryptJson(encrypted, key),
        throwsA(isA<DecryptionFailedException>()));
  });

  test('KDF ist deterministisch bei gleichen Parametern', () async {
    final params = testParams();
    final k1 = await crypto.deriveKey('passphrase', params);
    final k2 = await crypto.deriveKey('passphrase', params);
    expect(await k1.extractBytes(), await k2.extractBytes());
  });

  test('CryptoParams: JSON-Roundtrip', () {
    final params = CryptoParams.generate();
    final restored = CryptoParams.fromJson(params.toJson());
    expect(restored.salt, params.salt);
    expect(restored.memoryKiB, params.memoryKiB);
    expect(restored.iterations, params.iterations);
  });
}

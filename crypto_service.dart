import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// PBKDF2-HMAC-SHA256 producing one 32-byte block. Top-level so it can run
/// in a background isolate through compute().
List<int> pbkdf2Derive(Map<String, dynamic> a) {
  final hmac = hash.Hmac(hash.sha256, utf8.encode(a['p'] as String));
  final salt = (a['s'] as List).cast<int>();
  final iterations = a['i'] as int;
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  for (var n = 1; n < iterations; n++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return t;
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// All cryptography used by the app lives here.
///
/// Design (envelope encryption):
///  * A random 256-bit data key (DEK) encrypts the agency data (AES-256-GCM).
///  * The DEK is stored only in "wrapped" form: once under a key derived from
///    the password, once under a key derived from a recovery code.
///  * Cloud storage only ever receives ciphertext and the wrapped keys.
class CryptoService {
  static const kdfIterations = 120000;
  static const recoveryIterations = 60000;
  static final AesGcm _aes = AesGcm.with256bits();

  // 32 symbols, no 0/O/1/I, so a code can be read out and typed reliably.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static List<int> randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static String randomId() => randomBytes(12)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static Future<List<int>> deriveKey(
    String secret,
    List<int> salt, {
    int iterations = kdfIterations,
  }) {
    return compute(
        pbkdf2Derive, <String, dynamic>{'p': secret, 's': salt, 'i': iterations});
  }

  /// Encrypts [plain] and returns base64(nonce | ciphertext | tag).
  static Future<String> seal(List<int> key, List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
    return base64Encode(box.concatenation());
  }

  /// Returns the plaintext, or null when the key is wrong or data is damaged.
  static Future<List<int>?> open(List<int> key, String b64) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(b64),
        nonceLength: 12,
        macLength: 16,
      );
      return await _aes.decrypt(box, secretKey: SecretKey(key));
    } catch (_) {
      return null;
    }
  }

  /// 24 symbols = 120 bits, shown as XXXX-XXXX-XXXX-XXXX-XXXX-XXXX.
  static String newRecoveryCode() {
    final r = Random.secure();
    final chars =
        List<String>.generate(24, (_) => _alphabet[r.nextInt(_alphabet.length)]);
    return [
      for (var i = 0; i < 24; i += 4) chars.sublist(i, i + 4).join(),
    ].join('-');
  }

  static String normalizeCode(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

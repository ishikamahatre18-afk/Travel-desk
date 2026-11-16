import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'vault.dart';

/// PBKDF2-HMAC-SHA256 (single 32-byte block).
List<int> pbkdf2Derive(Map<String, dynamic> a) {
  final hmac = Hmac(sha256, utf8.encode(a['p'] as String));
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

enum LoginStatus { ok, wrong, locked }

class LoginResult {
  final LoginStatus status;
  final String message;
  const LoginResult(this.status, this.message);
}

class AuthService {
  static const _iterations = 120000;
  static const maxFreeAttempts = 5;

  static Future<bool> hasAccount() async =>
      (await Vault.read('auth_hash')) != null;

  static String? passwordProblem(String p) {
    if (p.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'[0-9]').hasMatch(p)) {
      return 'Mix letters and numbers.';
    }
    return null;
  }

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static String _norm(String user) => user.trim().toLowerCase();

  static Future<void> createAccount(String user, String password) async {
    final salt = _randomBytes(16);
    final hash = await compute(
        pbkdf2Derive, {'p': password, 's': salt, 'i': _iterations});
    await Vault.write('auth_user', _norm(user));
    await Vault.write('auth_salt', base64Encode(salt));
    await Vault.write('auth_hash', base64Encode(hash));
    await Vault.write('auth_iters', _iterations.toString());
    await Vault.write('auth_fails', '0');
    await Vault.delete('auth_lock_until');
  }

  static Future<LoginResult> login(String user, String password) async {
    final lockRaw = await Vault.read('auth_lock_until');
    final lockUntil = int.tryParse(lockRaw ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockUntil > now) {
      final secs = ((lockUntil - now) / 1000).ceil();
      return LoginResult(
          LoginStatus.locked, 'Too many attempts. Try again in $secs s.');
    }

    final storedUser = await Vault.read('auth_user') ?? '';
    final salt = base64Decode(await Vault.read('auth_salt') ?? '');
    final storedHash = base64Decode(await Vault.read('auth_hash') ?? '');
    final iters =
        int.tryParse(await Vault.read('auth_iters') ?? '') ?? _iterations;

    // Always run the hash so timing does not reveal whether the user exists.
    final hash =
        await compute(pbkdf2Derive, {'p': password, 's': salt, 'i': iters});
    final userOk = constantTimeEquals(
        utf8.encode(storedUser), utf8.encode(_norm(user)));
    final passOk = constantTimeEquals(hash, storedHash);

    if (userOk && passOk) {
      await Vault.write('auth_fails', '0');
      await Vault.delete('auth_lock_until');
      return const LoginResult(LoginStatus.ok, '');
    }

    final fails = (int.tryParse(await Vault.read('auth_fails') ?? '') ?? 0) + 1;
    await Vault.write('auth_fails', fails.toString());
    if (fails >= maxFreeAttempts) {
      final extra = min(fails - maxFreeAttempts, 5);
      final waitSecs = min(30 * pow(2, extra).toInt(), 900);
      await Vault.write('auth_lock_until',
          (DateTime.now().millisecondsSinceEpoch + waitSecs * 1000).toString());
      return LoginResult(LoginStatus.locked,
          'Too many attempts. Locked for $waitSecs s.');
    }
    return LoginResult(LoginStatus.wrong,
        'Incorrect username or password. ${maxFreeAttempts - fails} attempts left.');
  }

  /// Returns an error message, or null on success.
  static Future<String?> changePassword(String oldPw, String newPw) async {
    final user = await Vault.read('auth_user') ?? '';
    final r = await login(user, oldPw);
    if (r.status != LoginStatus.ok) return r.message;
    final problem = passwordProblem(newPw);
    if (problem != null) return problem;
    await createAccount(user, newPw);
    return null;
  }
}

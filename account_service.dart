import 'dart:convert';
import 'dart:math';

import 'crypto_service.dart';
import 'vault.dart';

/// One login on this phone. Holds only wrapped keys, never the password or
/// the data key itself.
class LocalAccount {
  final String id;
  final String name; // email (cloud) or username (phone only), lower-case
  final String kdfSalt;
  final String wrappedPw;
  final String recoverySalt;
  final String wrappedRecovery;
  final bool cloudLinked;

  const LocalAccount({
    required this.id,
    required this.name,
    required this.kdfSalt,
    required this.wrappedPw,
    required this.recoverySalt,
    required this.wrappedRecovery,
    this.cloudLinked = false,
  });

  LocalAccount copyWith({
    String? kdfSalt,
    String? wrappedPw,
    String? recoverySalt,
    String? wrappedRecovery,
    bool? cloudLinked,
  }) =>
      LocalAccount(
        id: id,
        name: name,
        kdfSalt: kdfSalt ?? this.kdfSalt,
        wrappedPw: wrappedPw ?? this.wrappedPw,
        recoverySalt: recoverySalt ?? this.recoverySalt,
        wrappedRecovery: wrappedRecovery ?? this.wrappedRecovery,
        cloudLinked: cloudLinked ?? this.cloudLinked,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kdfSalt': kdfSalt,
        'wrappedPw': wrappedPw,
        'recoverySalt': recoverySalt,
        'wrappedRecovery': wrappedRecovery,
        'cloudLinked': cloudLinked,
      };

  factory LocalAccount.fromJson(Map<String, dynamic> j) => LocalAccount(
        id: j['id'] as String,
        name: j['name'] as String,
        kdfSalt: j['kdfSalt'] as String,
        wrappedPw: j['wrappedPw'] as String,
        recoverySalt: j['recoverySalt'] as String,
        wrappedRecovery: j['wrappedRecovery'] as String,
        cloudLinked: j['cloudLinked'] == true,
      );
}

/// An unlocked login: the data key lives only in memory for this object.
class Session {
  final LocalAccount account;
  final List<int> dek;
  final String password; // memory only, used for cloud sign-in, never stored
  const Session(this.account, this.dek, this.password);

  Session withAccount(LocalAccount a, {String? password}) =>
      Session(a, dek, password ?? this.password);
}

enum UnlockStatus { ok, wrong, locked }

class UnlockResult {
  final UnlockStatus status;
  final String message;
  final List<int>? dek;
  const UnlockResult(this.status, this.message, [this.dek]);
}

class NewAccount {
  final LocalAccount account;
  final List<int> dek;
  final String recoveryCode;
  const NewAccount(this.account, this.dek, this.recoveryCode);
}

class AccountService {
  static const _registryKey = 'accounts_v2';
  static const maxFreeAttempts = 5;

  static String normName(String s) => s.trim().toLowerCase();

  static bool looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  static String? nameProblem(String name, {required bool needEmail}) {
    final n = name.trim();
    if (needEmail) {
      return looksLikeEmail(n) ? null : 'Enter a valid email address.';
    }
    return n.length >= 3 ? null : 'Username must be at least 3 characters.';
  }

  static String? passwordProblem(String p) {
    if (p.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'[0-9]').hasMatch(p)) {
      return 'Mix letters and numbers.';
    }
    return null;
  }

  // ---- registry -----------------------------------------------------------

  static Future<List<LocalAccount>> list() async {
    final raw = await Vault.read(_registryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => LocalAccount.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<LocalAccount> l) =>
      Vault.write(_registryKey, jsonEncode(l.map((e) => e.toJson()).toList()));

  static Future<void> upsert(LocalAccount a) async {
    final l = await list();
    final i = l.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      l[i] = a;
    } else {
      l.add(a);
    }
    await _saveAll(l);
  }

  static Future<LocalAccount?> findByName(String name) async {
    final n = normName(name);
    for (final a in await list()) {
      if (a.name == n) return a;
    }
    return null;
  }

  /// Removes the account from this phone only. A cloud copy is untouched.
  static Future<void> remove(String id) async {
    final l = await list();
    l.removeWhere((x) => x.id == id);
    await _saveAll(l);
    for (final k in ['data_', 'data_bad_', 'fails_', 'lock_', 'cloudver_', 'dirty_']) {
      await Vault.delete('$k$id');
    }
  }

  // ---- create / unlock ----------------------------------------------------

  static String _b64(List<int> b) => base64Encode(b);

  static Future<NewAccount> create(String name, String password) async {
    final dek = CryptoService.randomBytes(32);
    final salt = CryptoService.randomBytes(16);
    final rsalt = CryptoService.randomBytes(16);
    final code = CryptoService.newRecoveryCode();
    final kek = await CryptoService.deriveKey(password, salt);
    final rkek = await CryptoService.deriveKey(
      CryptoService.normalizeCode(code),
      rsalt,
      iterations: CryptoService.recoveryIterations,
    );
    final acc = LocalAccount(
      id: CryptoService.randomId(),
      name: normName(name),
      kdfSalt: _b64(salt),
      wrappedPw: await CryptoService.seal(kek, dek),
      recoverySalt: _b64(rsalt),
      wrappedRecovery: await CryptoService.seal(rkek, dek),
    );
    await upsert(acc);
    return NewAccount(acc, dek, code);
  }

  /// Builds a local account from a cloud backup row (new phone / reinstall).
  static Future<LocalAccount> adopt(String name, Map<String, dynamic> row) async {
    final acc = LocalAccount(
      id: CryptoService.randomId(),
      name: normName(name),
      kdfSalt: row['kdf_salt'] as String,
      wrappedPw: row['wrapped_dek_pw'] as String,
      recoverySalt: row['recovery_salt'] as String,
      wrappedRecovery: row['wrapped_dek_recovery'] as String,
      cloudLinked: true,
    );
    await upsert(acc);
    return acc;
  }

  static Future<UnlockResult> unlock(LocalAccount a, String password) async {
    final lockUntil = int.tryParse(await Vault.read('lock_${a.id}') ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockUntil > now) {
      final secs = ((lockUntil - now) / 1000).ceil();
      return UnlockResult(
          UnlockStatus.locked, 'Too many attempts. Try again in $secs s.');
    }

    final kek = await CryptoService.deriveKey(password, base64Decode(a.kdfSalt));
    final dek = await CryptoService.open(kek, a.wrappedPw);
    if (dek != null) {
      await Vault.write('fails_${a.id}', '0');
      await Vault.delete('lock_${a.id}');
      return UnlockResult(UnlockStatus.ok, '', dek);
    }

    final fails =
        (int.tryParse(await Vault.read('fails_${a.id}') ?? '') ?? 0) + 1;
    await Vault.write('fails_${a.id}', fails.toString());
    if (fails >= maxFreeAttempts) {
      final extra = min(fails - maxFreeAttempts, 5);
      final wait = min(30 * pow(2, extra).toInt(), 900);
      await Vault.write('lock_${a.id}',
          (DateTime.now().millisecondsSinceEpoch + wait * 1000).toString());
      return UnlockResult(
          UnlockStatus.locked, 'Too many attempts. Locked for $wait s.');
    }
    return UnlockResult(UnlockStatus.wrong,
        'Incorrect password. ${maxFreeAttempts - fails} attempts left.');
  }

  // ---- password and recovery ---------------------------------------------

  /// Re-wraps the data key under a new password. The data itself is not
  /// re-encrypted. Marks the account as changed so the cloud copy updates.
  static Future<LocalAccount> rewrapPassword(
      LocalAccount a, List<int> dek, String newPassword) async {
    final salt = CryptoService.randomBytes(16);
    final kek = await CryptoService.deriveKey(newPassword, salt);
    final updated = a.copyWith(
      kdfSalt: _b64(salt),
      wrappedPw: await CryptoService.seal(kek, dek),
    );
    await upsert(updated);
    await Vault.write('dirty_${a.id}', '1');
    return updated;
  }

  static Future<NewRecovery> newRecovery(LocalAccount a, List<int> dek) async {
    final rsalt = CryptoService.randomBytes(16);
    final code = CryptoService.newRecoveryCode();
    final rkek = await CryptoService.deriveKey(
      CryptoService.normalizeCode(code),
      rsalt,
      iterations: CryptoService.recoveryIterations,
    );
    final updated = a.copyWith(
      recoverySalt: _b64(rsalt),
      wrappedRecovery: await CryptoService.seal(rkek, dek),
    );
    await upsert(updated);
    await Vault.write('dirty_${a.id}', '1');
    return NewRecovery(updated, code);
  }

  /// Opens the data key with a recovery code. Null when the code is wrong.
  static Future<List<int>?> dekFromRecovery(
      String recoverySalt, String wrappedRecovery, String code) async {
    final rkek = await CryptoService.deriveKey(
      CryptoService.normalizeCode(code),
      base64Decode(recoverySalt),
      iterations: CryptoService.recoveryIterations,
    );
    return CryptoService.open(rkek, wrappedRecovery);
  }
}

class NewRecovery {
  final LocalAccount account;
  final String code;
  const NewRecovery(this.account, this.code);
}

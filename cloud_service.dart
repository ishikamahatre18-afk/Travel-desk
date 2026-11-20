import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../models.dart';
import 'account_service.dart';
import 'crypto_service.dart';
import 'vault.dart';

class SyncState {
  final String text;
  final bool ok;
  final bool busy;
  const SyncState(this.text, {this.ok = false, this.busy = false});
}

class CloudFetch {
  final String? error;
  final Map<String, dynamic>? row;
  const CloudFetch({this.error, this.row});
}

/// Encrypted cloud backup on Supabase.
///
/// Only ciphertext and wrapped keys are uploaded. Row Level Security limits
/// every login to its own row. The password is kept in memory only while the
/// app is unlocked, and the cloud session is dropped when the app locks.
class CloudService {
  static final CloudService instance = CloudService._();
  CloudService._();

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anon = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get configured => _url.isNotEmpty && _anon.isNotEmpty;

  SupabaseClient? _client;
  SupabaseClient get _c => _client ??= SupabaseClient(_url, _anon);

  final ValueNotifier<SyncState> state = ValueNotifier(
      SyncState(configured ? 'Not synced yet' : 'Cloud backup is not set up'));

  LocalAccount? _account;
  List<int>? _dek;
  String? _password;
  Timer? _timer;
  bool _running = false;

  void _set(String text, {bool ok = false, bool busy = false}) {
    state.value = SyncState(text, ok: ok, busy: busy);
  }

  // ---- lifecycle ----------------------------------------------------------

  void attach(Session s) {
    _account = s.account;
    _dek = s.dek;
    _password = s.password;
    DataStore.instance.onLocalSave = scheduleSync;
    if (!configured) {
      _set('Cloud backup is not set up. Data is on this phone only.');
      return;
    }
    scheduleSync(delay: Duration.zero);
  }

  /// Call after the password or recovery wrapper changed.
  void updateAccount(LocalAccount a, {String? password}) {
    _account = a;
    if (password != null) _password = password;
    scheduleSync(delay: Duration.zero);
  }

  Future<void> detach() async {
    _timer?.cancel();
    _timer = null;
    DataStore.instance.onLocalSave = null;
    _account = null;
    _dek = null;
    _password = null;
    if (_client != null) {
      try {
        await _client!.auth.signOut();
      } catch (_) {}
    }
    _set(configured ? 'Locked' : 'Cloud backup is not set up');
  }

  void scheduleSync({Duration delay = const Duration(seconds: 2)}) {
    if (!configured) return;
    _timer?.cancel();
    _timer = Timer(delay, sync);
  }

  // ---- auth helpers -------------------------------------------------------

  Future<String?> signUp(String email, String password) async {
    try {
      final res = await _c.auth.signUp(email: email, password: password);
      if (res.session == null) return 'confirm';
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'offline';
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await _c.auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'offline';
    }
  }

  /// New phone or reinstall: sign in and download the encrypted backup row.
  Future<CloudFetch> signInAndFetch(String email, String password) async {
    final err = await signIn(email, password);
    if (err != null) return CloudFetch(error: err);
    try {
      final uid = _c.auth.currentUser!.id;
      final row =
          await _c.from('vaults').select().eq('user_id', uid).maybeSingle();
      return CloudFetch(row: row);
    } catch (e) {
      return CloudFetch(error: _describe(e));
    }
  }

  Future<void> signOutQuietly() async {
    try {
      await _client?.auth.signOut();
    } catch (_) {}
  }

  /// Changes the cloud login password. Best effort; returns an error or null.
  Future<String?> changeCloudPassword(String newPassword) async {
    if (!configured || _c.auth.currentUser == null) return 'not signed in';
    try {
      await _c.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'offline';
    }
  }

  static String _describe(Object e) {
    if (e is PostgrestException) return e.message;
    if (e is AuthException) return e.message;
    return 'network problem';
  }

  // ---- sync ---------------------------------------------------------------

  Future<void> sync() async {
    final a = _account;
    final dek = _dek;
    final pw = _password;
    if (!configured || a == null || dek == null || pw == null || _running) return;
    _running = true;
    _set('Syncing…', busy: true);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final retry = await _syncOnce(a, dek, pw);
        if (!retry) break;
      }
    } catch (e) {
      _set('Could not sync (${_describe(e)}). Will retry.');
    } finally {
      _running = false;
    }
  }

  /// Returns true when another attempt is needed (version conflict).
  Future<bool> _syncOnce(LocalAccount a, List<int> dek, String pw) async {
    var acct = _account ?? a;

    if (_c.auth.currentUser == null) {
      var err = await signIn(acct.name, pw);
      if (err != null &&
          !acct.cloudLinked &&
          AccountService.looksLikeEmail(acct.name) &&
          err.toLowerCase().contains('invalid')) {
        err = await signUp(acct.name, pw);
        if (err == 'confirm') {
          _set('Check your email to confirm your account, then lock and unlock the app.');
          return false;
        }
      }
      if (err == 'offline') {
        _set('Offline. Saved on this phone, will back up later.');
        return false;
      }
      if (err != null) {
        _set('Cloud sign-in failed: $err');
        return false;
      }
    }

    final uid = _c.auth.currentUser!.id;
    final store = DataStore.instance;
    final id = acct.id;
    final localBlob = await Vault.read('data_$id');
    final dirty = (await Vault.read('dirty_$id')) == '1';
    final baseVer = int.tryParse(await Vault.read('cloudver_$id') ?? '') ?? 0;
    final row = await _c.from('vaults').select().eq('user_id', uid).maybeSingle();

    // First upload for this login.
    if (row == null) {
      final blob = localBlob ?? await store.encryptedBlob();
      await _c.from('vaults').insert({
        'user_id': uid,
        'kdf_salt': acct.kdfSalt,
        'wrapped_dek_pw': acct.wrappedPw,
        'recovery_salt': acct.recoverySalt,
        'wrapped_dek_recovery': acct.wrappedRecovery,
        'data_blob': blob,
        'version': 1,
      });
      await Vault.write('cloudver_$id', '1');
      await Vault.write('dirty_$id', '0');
      await _markLinked(acct);
      _set('Backed up just now', ok: true);
      return false;
    }

    final cloudVer = (row['version'] as num).toInt();
    var needPush = dirty;

    if (cloudVer > baseVer) {
      final cloudBlob = (row['data_blob'] as String?) ?? '';
      if (cloudBlob.isNotEmpty) {
        final plain = await CryptoService.open(dek, cloudBlob);
        if (plain == null) {
          _set('Cloud backup was made with a different key. Sign in again.');
          return false;
        }
        final cloudJson = utf8.decode(plain);
        if (localBlob == null || !dirty) {
          store.replaceFrom(cloudJson);
        } else {
          store.mergeFrom(cloudJson);
          needPush = true;
        }
        await store.saveFromSync();
      }
    }

    if (needPush) {
      final blob = await store.encryptedBlob();
      final res = await _c
          .from('vaults')
          .update({
            'kdf_salt': acct.kdfSalt,
            'wrapped_dek_pw': acct.wrappedPw,
            'recovery_salt': acct.recoverySalt,
            'wrapped_dek_recovery': acct.wrappedRecovery,
            'data_blob': blob,
            'version': cloudVer + 1,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', uid)
          .eq('version', cloudVer)
          .select();
      if (res.isEmpty) {
        // Another device saved first. Pull and merge again.
        return true;
      }
      await Vault.write('cloudver_$id', '${cloudVer + 1}');
    } else {
      await Vault.write('cloudver_$id', '$cloudVer');
    }
    await Vault.write('dirty_$id', '0');
    await _markLinked(acct);
    _set('Backed up just now', ok: true);
    return false;
  }

  Future<void> _markLinked(LocalAccount a) async {
    if (a.cloudLinked) return;
    final linked = a.copyWith(cloudLinked: true);
    await AccountService.upsert(linked);
    _account = linked;
  }
}

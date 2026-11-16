import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over Android Keystore-backed encrypted storage.
class Vault {
  static const FlutterSecureStorage _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> read(String key) => _s.read(key: key);
  static Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  static Future<void> delete(String key) => _s.delete(key: key);
}

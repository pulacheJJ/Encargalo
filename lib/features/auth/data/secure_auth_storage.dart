import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SessionVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreSessionVault implements SessionVault {
  final FlutterSecureStorage storage;
  const KeystoreSessionVault([
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

/// Supabase still owns session lifecycle/refresh. Only the persistence boundary
/// changes to Android Keystore; the password is never stored by this adapter.
class SecureAuthStorage extends LocalStorage {
  final String key;
  final SessionVault vault;
  late final SharedPreferences _legacy;
  SecureAuthStorage(String projectUrl, {SessionVault? vault})
    : key = 'sb-${Uri.parse(projectUrl).host.split('.').first}-auth-token',
      vault = vault ?? const KeystoreSessionVault();

  @override
  Future<void> initialize() async {
    _legacy = await SharedPreferences.getInstance();
    await _legacy.reload();
    if (await vault.read(key) == null) {
      final previous = _legacy.getString(key);
      if (previous != null) {
        // Remove the old copy only AFTER a confirmed secure write/read.
        await vault.write(key, previous);
        if (await vault.read(key) != previous) {
          throw StateError('No se pudo proteger la sesión.');
        }
      }
    }
    await _legacy.remove(key);
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => vault.read(key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      vault.write(key, persistSessionString);
  @override
  Future<void> removePersistedSession() async {
    await vault.delete(key);
    await _legacy.remove(key);
  }
}

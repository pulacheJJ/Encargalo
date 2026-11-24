import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encargalo/features/auth/data/secure_auth_storage.dart';

class MemoryVault implements SessionVault {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('vault no disponible');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'sb-project-auth-token';
  test(
    'Migra sesión después de confirmar escritura segura; conserva preferencias',
    () async {
      SharedPreferences.setMockInitialValues({
        key: 'sesion-fixture',
        'theme': 'dark',
      });
      final vault = MemoryVault();
      final storage = SecureAuthStorage(
        'https://project.supabase.co',
        vault: vault,
      );
      await storage.initialize();
      expect(await storage.accessToken(), 'sesion-fixture');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(key), isFalse);
      expect(prefs.getString('theme'), 'dark');
      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    },
  );
  test('Un fallo del almacén seguro no borra la sesión anterior', () async {
    SharedPreferences.setMockInitialValues({key: 'sesion-fixture'});
    final vault = MemoryVault()..fail = true;
    await expectLater(
      SecureAuthStorage(
        'https://project.supabase.co',
        vault: vault,
      ).initialize(),
      throwsStateError,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(key),
      'sesion-fixture',
    );
  });
  test(
    'La sesión segura vigente no se sustituye por una copia antigua',
    () async {
      SharedPreferences.setMockInitialValues({key: 'anterior'});
      final vault = MemoryVault()..values[key] = 'vigente';
      final storage = SecureAuthStorage(
        'https://project.supabase.co',
        vault: vault,
      );
      await storage.initialize();
      expect(await storage.accessToken(), 'vigente');
      await storage.persistSession('renovada');
      expect(await storage.accessToken(), 'renovada');
    },
  );
}

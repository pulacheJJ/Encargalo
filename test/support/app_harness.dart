import 'package:encargalo/app/app_state.dart';
import 'package:encargalo/core/background/sync_service.dart';
import 'package:encargalo/core/network/api_client.dart';
import 'package:encargalo/core/storage/local_database.dart';
import 'package:encargalo/features/auth/data/supabase_auth_gateway.dart';
import 'package:encargalo/features/marketplace/data/market_repository.dart';
import 'package:encargalo/features/profile/data/profile_repository.dart';
import 'package:encargalo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_backend.dart';

/// La app real, con la comprobación de configuración resuelta para poder
/// recorrer el mismo árbol de pantallas sin claves ni proyecto cloud.
class TestAppState extends AppState {
  TestAppState({super.sessionEffects});

  @override
  bool get configured => true;
}

/// Monta `EncargaloApp` con sesión real sobre `FakeBackend`, SQLite en memoria
/// y preferencias simuladas. Cada prueba recibe un estado limpio.
class AppFixture {
  AppFixture._({
    required this.app,
    required this.backend,
    required this.db,
    required this.cloud,
    required this.api,
  });

  final TestAppState app;
  final FakeBackend backend;
  final Database db;
  final SupabaseClient cloud;
  final ApiClient api;

  static Future<AppFixture> create(FakeBackend backend) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 2, onCreate: LocalDatabase.create),
    );
    final cloud = SupabaseClient(
      'https://fixture.invalid',
      'fixture-public',
      httpClient: backend.client,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final api = ApiClient(
      baseUrl: 'https://fixture.invalid',
      publicKey: 'fixture-public',
      token: () async => cloud.auth.currentSession?.accessToken,
      client: backend.client,
    );
    final app = TestAppState(sessionEffects: (_) async {});
    app.local = LocalDatabase(db);
    app.prefs = await SharedPreferences.getInstance();
    app.repository = MarketRepository(api, cloud);
    app.authentication = SupabaseAuthGateway(cloud.auth);
    app.profiles = ProfileRepository(api);
    app.sync = SyncService(app.local!, app.repository!);
    app.loading = false;
    return AppFixture._(
      app: app,
      backend: backend,
      db: db,
      cloud: cloud,
      api: api,
    );
  }

  Future<void> signIn(String email) =>
      app.signIn(email, backend.passwordFor(email));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const EncargaloApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    api.close();
    await cloud.dispose();
    await db.close();
  }
}

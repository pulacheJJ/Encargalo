import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:encargalo/app/app_state.dart';
import 'package:encargalo/core/network/api_client.dart';
import 'package:encargalo/core/storage/local_database.dart';
import 'package:encargalo/features/auth/data/supabase_auth_gateway.dart';
import 'package:encargalo/features/marketplace/data/market_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'Primer ingreso abre cuenta sin esperar FCM ni un segundo evento',
    () async {
      const id = '11111111-1111-4111-8111-111111111111';
      final claims = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': id,
                'role': 'authenticated',
                'exp':
                    DateTime.now()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch ~/
                    1000,
              }),
            ),
          )
          .replaceAll('=', '');
      final jwt = 'eyJhbGciOiJIUzI1NiJ9.$claims.fixture';
      var authCalls = 0, profileCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/v1/token')) {
          authCalls++;
          return http.Response(
            jsonEncode({
              'access_token': jwt,
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': id,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.invalid',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-01-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/profiles')) {
          profileCalls++;
          return http.Response(
            jsonEncode([
              {
                'id': id,
                'name': 'Prueba',
                'role': 'cliente',
                'district': 'Piura',
                'description': '',
                'categories': [],
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/categories')) {
          return http.Response('[{"id":"bordado","name":"Bordado"}]', 200);
        }
        return http.Response('{}', 404);
      });
      final cloud = SupabaseClient(
        'https://fixture.invalid',
        'fixture-public',
        httpClient: client,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      SharedPreferences.setMockInitialValues({});
      final effects = Completer<void>();
      final app = AppState(sessionEffects: (_) => effects.future);
      app.local = LocalDatabase(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: LocalDatabase.create,
          ),
        ),
      );
      app.prefs = await SharedPreferences.getInstance();
      app.repository = MarketRepository(
        ApiClient(
          baseUrl: 'https://fixture.invalid/rest/v1',
          publicKey: 'fixture-public',
          token: () async => cloud.auth.currentSession?.accessToken,
          client: client,
        ),
        cloud,
      );
      // Use the real Auth SDK over a test HTTP boundary, not a production login mode.
      app.authentication = SupabaseAuthGateway(cloud.auth);
      try {
        await app.signIn('fixture@example.invalid', 'fixture-password');
        expect(app.owner, id);
        expect(app.loading, isFalse);
        expect(authCalls, 1);
        expect(profileCalls, 1);
        expect(effects.isCompleted, isFalse);
        expect(app.prefs!.getString('active_user'), id);
      } finally {
        effects.complete();
        app.dispose();
        await app.local!.db.close();
        await cloud.dispose();
      }
    },
  );
}

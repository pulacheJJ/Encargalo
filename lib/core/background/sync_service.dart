import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../../app/config.dart';
import '../domain/models.dart';
import '../../features/marketplace/data/market_repository.dart';
import '../network/api_client.dart';
import '../storage/local_database.dart';
import '../../features/auth/data/secure_auth_storage.dart';

ApiClient authenticatedApi(SupabaseClient cloud) => ApiClient(
  baseUrl: AppConfig.supabaseUrl,
  publicKey: AppConfig.supabaseKey,
  token: () async {
    final s = cloud.auth.currentSession;
    if (s == null) return null;
    if (s.isExpired) {
      try {
        await cloud.auth.refreshSession();
      } on AuthRetryableFetchException {
        throw ApiFailure(
          'No se pudo renovar la sesión sin conexión. Se conservan los borradores.',
          retryable: true,
        );
      }
    }
    return cloud.auth.currentSession?.accessToken;
  },
);

class SyncService {
  final LocalDatabase local;
  final MarketRepository remote;
  bool busy = false;
  SyncService(this.local, this.remote);
  Future<bool> run(String owner) async {
    if (busy) return false;
    busy = true;
    try {
      for (var i = 0; i < 20; i++) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        if (prefs.getString('active_user') != owner ||
            remote.cloud.auth.currentUser?.id != owner) {
          return true;
        }
        final operation = await local.claim(owner);
        if (operation == null) break;
        try {
          final payload = jsonDecode(operation['payload'] as String) as Json;
          if (operation['action'] == 'quote') {
            if (payload['owner_id'] != owner) {
              throw ApiFailure('La propuesta pertenece a otra cuenta.');
            }
            final q = await remote.submitQuote(
              Map<String, dynamic>.from(payload['data']),
              operation['id'],
              payload['expected_version'],
              owner: owner,
            );
            await local.confirmed(operation, q.version);
            await prefs.setString(
              'last_sync_$owner',
              DateTime.now().toUtc().toIso8601String(),
            );
            continue;
          }
          final d = RequestDraft.fromLocal(payload);
          if (d.ownerId != owner) {
            throw ApiFailure('El borrador pertenece a otra cuenta.');
          }
          final version =
              operation['action'] == 'delete'
                  ? await (() async {
                    await remote.deleteRequest(d, operation['id']);
                    return d.remoteVersion + 1;
                  })()
                  : await remote.publish(d, operation['id']);
          await local.confirmed(operation, version);
          await prefs.setString(
            'last_sync_$owner',
            DateTime.now().toUtc().toIso8601String(),
          );
        } catch (e) {
          await local.failed(
            operation,
            e.toString(),
            retryable: e is ApiFailure ? e.retryable : true,
          );
        }
      }
      return (await local.pending(owner)).isEmpty;
    } finally {
      busy = false;
    }
  }
}

@pragma('vm:entry-point')
void syncDispatcher() {
  Workmanager().executeTask((task, data) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!AppConfig.configured) return true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final owner = data?['owner'] as String?;
    if (owner == null || prefs.getString('active_user') != owner) return true;
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureAuthStorage(AppConfig.supabaseUrl),
        ),
      );
      final cloud = Supabase.instance.client;
      if (cloud.auth.currentUser?.id != owner) return true;
      final local = await LocalDatabase.open();
      final api = authenticatedApi(cloud);
      try {
        return await SyncService(
          local,
          MarketRepository(api, cloud),
        ).run(owner);
      } finally {
        api.close();
        await local.db.close();
      }
    } catch (_) {
      return false;
    }
  });
}

Future<void> scheduleSync(String owner) async {
  if (!Platform.isAndroid) return;
  await Workmanager().registerOneOffTask(
    'encargalo-sync-$owner',
    'sync',
    tag: owner,
    inputData: {'owner': owner},
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'config.dart';
import '../core/domain/models.dart';
import '../features/marketplace/data/market_repository.dart';
import '../core/storage/local_database.dart';
import '../core/notifications/push_service.dart';
import '../core/background/sync_service.dart';
import '../core/device/hardware_services.dart';
import '../core/network/api_client.dart';
import '../core/async/single_flight.dart';
import '../features/auth/domain/auth_gateway.dart';
import '../features/auth/data/supabase_auth_gateway.dart';
import '../features/auth/data/secure_auth_storage.dart';
import '../features/profile/domain/profile_gateway.dart';
import '../features/profile/data/profile_repository.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final Future<void> Function(String uid)? sessionEffects;
  AppState({this.sessionEffects});
  bool loading = true;
  String? error, warning;
  Profile? profile;
  List<Category> categories = [];
  ThemeMode themeMode = ThemeMode.system;
  LocalDatabase? local;
  MarketRepository? repository;
  SyncService? sync;
  PushService? push;
  SharedPreferences? prefs;
  StreamSubscription<AuthState>? _auth;
  RealtimeChannel? _channel;
  Timer? _repaint;
  int revision = 0, _generation = 0;
  Json? pendingRoute;
  bool recovering = false;
  bool _disposed = false;
  AuthGateway? authentication;
  ProfileGateway? profiles;
  final _sessionFlight = SingleFlight<void>();
  Future<void>? _pushInitialization;
  static const _realtimeWarning =
      'No se pudo conectar a cambios en vivo. Actualiza la pantalla para consultar la nube.';
  bool get configured => AppConfig.configured;
  bool get isBusiness => profile?.isBusiness ?? false;
  String? get owner => profile?.id;
  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      WidgetsBinding.instance.addObserver(this);
      prefs = await SharedPreferences.getInstance();
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == prefs!.getString('theme'),
        orElse: () => ThemeMode.system,
      );
      local ??= await LocalDatabase.open();
      if (Platform.isAndroid) await Workmanager().initialize(syncDispatcher);
      if (!configured) {
        loading = false;
        notifyListeners();
        return;
      }
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureAuthStorage(AppConfig.supabaseUrl),
        ),
      );
      final cloud = Supabase.instance.client;
      authentication = SupabaseAuthGateway(cloud.auth);
      repository = MarketRepository(authenticatedApi(cloud), cloud);
      profiles = ProfileRepository(repository!.api);
      sync = SyncService(local!, repository!);
      push = PushService(repository!, local!, (data) {
        pendingRoute = data;
        notifyListeners();
      });
      _auth = cloud.auth.onAuthStateChange.listen(
        (state) {
          if (state.event == AuthChangeEvent.tokenRefreshed &&
              state.session?.user.id == owner &&
              profile != null) {
            return;
          }
          if (state.event == AuthChangeEvent.passwordRecovery) {
            recovering = true;
            notifyListeners();
          }
          // Auth callbacks must return before SDK-dependent asynchronous work.
          scheduleMicrotask(() {
            if (!_disposed) unawaited(_session());
          });
        },
        onError: (Object e) {
          error = 'No se pudo recuperar la sesión. Vuelva a iniciar sesión.';
          notifyListeners();
        },
      );
      await _session();
    } catch (e) {
      error = 'No se pudo iniciar la aplicación: $e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await authentication!.signIn(email, password);
    await _session();
    if (profile == null && error != null) throw ApiFailure(error!);
  }

  Future<RegistrationResult> registerAccount({
    required String email,
    required String password,
    required Json metadata,
  }) async {
    final result = await authentication!.register(
      email: email,
      password: password,
      metadata: metadata,
    );
    if (!result.confirmationRequired) await _session();
    return result;
  }

  Future<void> _session() => _sessionFlight.run(
    repository!.cloud.auth.currentUser?.id ?? 'signed-out',
    _loadSession,
  );

  Future<void> _loadSession() async {
    final generation = ++_generation;
    final uid = repository!.cloud.auth.currentUser?.id;
    if (uid == null) {
      profile = null;
      categories = [];
      await prefs!.remove('active_user');
      await _unsubscribe();
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final results = await Future.wait<Object>([
        repository!.profile(),
        repository!.categories(),
      ]);
      final p = results[0] as Profile;
      final c = results[1] as List<Category>;
      if (generation != _generation) return;
      profile = p;
      categories = c;
      await local!.cache(
        'identity:$uid',
        jsonEncode({
          'profile': p.toJson(),
          'categories': c.map((item) => item.toJson()).toList(),
        }),
        const Duration(days: 30),
      );
      error = null;
      await prefs!.setString('active_user', uid);
      // Account identity is ready. FCM, Realtime and housekeeping are not
      // prerequisites for entering the app and must not block first login.
      loading = false;
      notifyListeners();
      unawaited(_afterSession(uid, generation));
    } catch (e) {
      if (generation == _generation) {
        final cached =
            e is ApiFailure && e.retryable
                ? await local!.cached('identity:$uid')
                : null;
        if (cached != null) {
          final data = jsonDecode(cached) as Json;
          profile = Profile.fromJson(
            Map<String, dynamic>.from(data['profile']),
          );
          categories =
              (data['categories'] as List)
                  .map(
                    (item) =>
                        Category.fromJson(Map<String, dynamic>.from(item)),
                  )
                  .toList();
          await prefs!.setString('active_user', uid);
          warning =
              'No se pudo confirmar conexión. Se usa el perfil en caché para recuperar borradores; publicar requiere respuesta de la nube.';
          unawaited(_afterSession(uid, generation));
        } else {
          error = e.toString();
        }
      }
    }
    if (generation == _generation) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _afterSession(String uid, int generation) async {
    bool active() => !_disposed && generation == _generation && owner == uid;
    try {
      if (sessionEffects != null) {
        await sessionEffects!(uid);
        return;
      }
      await _subscribe(uid);
      if (!active()) return;
      await recoverCamera();
      await CameraService().cleanOrphans(await local!.referencedPaths());
      if (!active()) return;
      try {
        await (_pushInitialization ??= push!.initialize());
        if (active()) {
          await push!.register().timeout(const Duration(seconds: 12));
        }
      } catch (_) {
        _pushInitialization = null;
        if (active()) {
          warning =
              'Puedes reintentar las notificaciones desde tu perfil; tu cuenta ya está disponible.';
        }
      }
      if (active()) await synchronize();
    } catch (_) {
      if (active()) {
        warning =
            'Algunas tareas siguen pendientes. Puedes reintentarlas desde Sincronización.';
      }
    } finally {
      if (active()) notifyListeners();
    }
  }

  Future<void> _unsubscribe() async {
    _repaint?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) await repository?.cloud.removeChannel(channel);
  }

  Future<void> _subscribe(String uid) async {
    final generation = _generation;
    await _unsubscribe();
    final cloud = repository!.cloud;
    final session = cloud.auth.currentSession;
    if (_disposed || generation != _generation || session?.user.id != uid) {
      return;
    }
    try {
      await cloud.realtime.setAuth(session!.accessToken);
    } catch (_) {
      if (!_disposed && generation == _generation) warning = _realtimeWarning;
      return;
    }
    if (_disposed || generation != _generation) return;
    final channel = cloud.channel('market-$uid');
    _channel = channel;
    bool active() =>
        !_disposed && generation == _generation && identical(_channel, channel);
    for (final table in [
      'requests',
      'quotes',
      'orders',
      'order_history',
      'notifications',
      'order_payments',
      'order_cancellations',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (p) {
          if (!active()) return;
          // UI coalescing only, not a replacement for Android WorkManager.
          _repaint?.cancel();
          _repaint = Timer(const Duration(milliseconds: 100), () {
            if (active()) changed();
          });
        },
      );
    }
    // The Phoenix join can precede PostgreSQL replication readiness. Refresh
    // after the system acknowledgement, including each automatic reconnect,
    // so changes made during the connection gap are fetched from the server.
    channel.onSystemEvents((payload) {
      if (!active() || payload is! Map) return;
      if (payload['extension'] == 'postgres_changes' &&
          payload['status'] == 'ok') {
        if (warning == _realtimeWarning) warning = null;
        repository?.invalidate();
        revision++;
        notifyListeners();
      }
    });
    channel.subscribe((status, error) {
      if (!active()) return;
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        warning = _realtimeWarning;
        notifyListeners();
      }
    });
  }

  Future<void> recoverCamera() async {
    final draftId = prefs!.getString('camera_draft');
    final cameraOwner = prefs!.getString('camera_owner');
    if (draftId == null || cameraOwner != owner) return;
    try {
      final recovered = await CameraService().recover();
      final d = await local!.draft(draftId, owner!);
      if (d != null && d.syncState != 'pending') {
        d.photos.addAll(recovered.take(3 - d.photos.length));
        await local!.saveDraft(d);
      }
      await prefs!.remove('camera_draft');
      await prefs!.remove('camera_owner');
    } catch (_) {
      warning =
          'No se pudo recuperar una foto interrumpida. El borrador se conserva.';
    }
  }

  Future<void> synchronize() async {
    final uid = owner;
    if (uid == null || sync == null) return;
    try {
      await scheduleSync(uid);
      await sync!.run(uid);
      if (!_disposed && uid == owner) changed();
    } catch (_) {
      if (!_disposed && uid == owner) {
        warning =
            'No se completó la sincronización. Tus borradores se conservan; reintenta desde Sincronización.';
        notifyListeners();
      }
    }
  }

  Future<void> signOut() async {
    final uid = owner;
    repository?.invalidate();
    await prefs!.remove('active_user');
    if (Platform.isAndroid && uid != null) await Workmanager().cancelByTag(uid);
    await _unsubscribe();
    try {
      await push?.detach();
    } catch (_) {
      warning =
          'No se retiró el token del servidor; este dispositivo ignorará avisos de la cuenta cerrada.';
    }
    profile = null;
    pendingRoute = null;
    recovering = false;
    revision++;
    await repository!.cloud.auth.signOut(scope: SignOutScope.local);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    await prefs!.setString('theme', mode.name);
    notifyListeners();
  }

  Future<void> refreshProfile() {
    repository?.invalidate();
    return _session();
  }

  void clearRoute() {
    pendingRoute = null;
  }

  void changed() {
    repository?.invalidate();
    revision++;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && owner != null) {
      unawaited(synchronize());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth?.cancel());
    unawaited(_unsubscribe());
    unawaited(push?.dispose());
    super.dispose();
  }
}

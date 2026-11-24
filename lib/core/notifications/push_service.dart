import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config.dart';
import '../domain/models.dart';
import '../../features/marketplace/data/market_repository.dart';
import '../storage/local_database.dart';

final localNotifications = FlutterLocalNotificationsPlugin();
const channel = AndroidNotificationChannel(
  'encargalo_orders',
  'Cotizaciones y pedidos',
  description: 'Eventos de solicitudes y pedidos',
  importance: Importance.high,
);
Future<void> initLocalNotifications({void Function(String)? onOpen}) async {
  await localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
    ),
    onDidReceiveNotificationResponse: (r) {
      if (r.payload != null) onOpen?.call(r.payload!);
    },
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

Future<void> displayPush(RemoteMessage message, LocalDatabase db) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final data = message.data;
  final id = data['event_id'];
  if (id == null ||
      data['recipient_id'] != prefs.getString('active_user') ||
      !(prefs.getBool('push_enabled') ?? true)) {
    return;
  }
  if (!await db.firstEvent(id)) return;
  await localNotifications.show(
    int.parse(id.replaceAll('-', '').substring(0, 7), radix: 16),
    data['title'],
    data['body'],
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'encargalo_orders',
        'Cotizaciones y pedidos',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(data),
  );
}

@pragma('vm:entry-point')
Future<void> firebaseBackground(RemoteMessage message) async {
  if (!AppConfig.pushConfigured) return;
  await Firebase.initializeApp(options: AppConfig.firebaseOptions);
  await initLocalNotifications();
  final db = await LocalDatabase.open();
  try {
    await displayPush(message, db);
  } finally {
    await db.db.close();
  }
}

class PushService {
  final MarketRepository remote;
  final LocalDatabase db;
  final void Function(Json) onOpen;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground, _opened;
  PushService(this.remote, this.db, this.onOpen);
  Future<void> initialize() async {
    if (!AppConfig.pushConfigured) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: AppConfig.firebaseOptions);
    }
    FirebaseMessaging.onBackgroundMessage(firebaseBackground);
    await initLocalNotifications(
      onOpen:
          (payload) => onOpen(Map<String, dynamic>.from(jsonDecode(payload))),
    );
    _foreground = FirebaseMessaging.onMessage.listen((m) => displayPush(m, db));
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => onOpen(m.data),
    );
    // HTTP v1 utiliza registration tokens; se conserva esa API compatible.
    // ignore: deprecated_member_use
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => register(token),
    );
    final launch = await localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload != null) {
      onOpen(
        Map<String, dynamic>.from(
          jsonDecode(launch!.notificationResponse!.payload!),
        ),
      );
    }
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) onOpen(initial.data);
  }

  Future<void> register([String? token]) async {
    if (!AppConfig.pushConfigured || remote.cloud.auth.currentUser == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('push_enabled') ?? true)) return;
    final device = prefs.getString('device_id') ?? uuid.v4();
    await prefs.setString('device_id', device);
    // No se envía un Firebase Installation ID donde HTTP v1 exige un token.
    // ignore: deprecated_member_use
    final t = token ?? await FirebaseMessaging.instance.getToken();
    if (t != null) {
      await remote.api.rpc('register_device', {
        'p_device': device,
        'p_token': t,
      });
    }
  }

  Future<bool> enable() async {
    if (!AppConfig.pushConfigured) return false;
    final p = await FirebaseMessaging.instance.requestPermission();
    final granted =
        p.authorizationStatus == AuthorizationStatus.authorized ||
        p.authorizationStatus == AuthorizationStatus.provisional;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_enabled', granted);
    if (granted) await register();
    return granted;
  }

  Future<void> detach() async {
    if (!AppConfig.pushConfigured) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final device = prefs.getString('device_id');
      if (device != null) {
        await remote.api.send(
          'DELETE',
          'rest/v1/device_tokens',
          query: {'device_id': 'eq.$device', 'owner_id': 'eq.${remote.userId}'},
        );
      }
    } finally {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
      await localNotifications.cancelAll();
    }
  }

  Future<void> dispose() async {
    await _refresh?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
  }
}

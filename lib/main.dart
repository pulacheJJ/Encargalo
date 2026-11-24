import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'app/theme.dart';
import 'features/auth/presentation/auth_screens.dart';
import 'features/home/presentation/home_shell.dart';
import 'features/marketplace/presentation/market_screens.dart';
import 'app/app_state.dart';
import 'core/widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Catálogo territorial: peru-code-dev/ubigeo-peru',
    ], await rootBundle.loadString('assets/locations/LICENSE.txt'));
  });
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: const EncargaloApp(),
    ),
  );
}

class EncargaloApp extends StatefulWidget {
  const EncargaloApp({super.key});
  @override
  State<EncargaloApp> createState() => _EncargaloAppState();
}

class _EncargaloAppState extends State<EncargaloApp> {
  final navigator = GlobalKey<NavigatorState>();
  String? lastOwner;
  bool handling = false;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (lastOwner != app.owner) {
      lastOwner = app.owner;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigator.currentState?.popUntil((r) => r.isFirst);
      });
    }
    if (app.pendingRoute != null && app.owner != null && !handling) {
      handling = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final route = app.pendingRoute;
        app.clearRoute();
        if (route != null && route['recipient_id'] == app.owner) {
          final order = route['order_id'] as String?;
          final request = route['request_id'] as String?;
          if (order != null && order.isNotEmpty) {
            await navigator.currentState?.push(
              MaterialPageRoute(builder: (_) => OrderDetailScreen(order)),
            );
          } else if (request != null && request.isNotEmpty) {
            await navigator.currentState?.push(
              MaterialPageRoute(builder: (_) => RequestDetailScreen(request)),
            );
          }
        }
        handling = false;
      });
    }
    return MaterialApp(
      title: 'Encárgalo',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigator,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: app.themeMode,
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home:
          app.loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : !app.configured
              ? const ConfigurationScreen()
              : app.recovering
              ? const RecoveryScreen(update: true)
              : app.profile != null
              ? HomeScreen(key: ValueKey(app.owner))
              : app.error != null &&
                  app.repository?.cloud.auth.currentUser != null
              ? Scaffold(
                body: PageBody(
                  children: [
                    EmptyState('No se pudo cargar tu cuenta', app.error!),
                    TaskButton('Reintentar', action: app.refreshProfile),
                    TaskButton('Cerrar sesión', action: app.signOut),
                  ],
                ),
              )
              : const AuthScreen(),
    );
  }
}

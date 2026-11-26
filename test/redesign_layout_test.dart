import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:encargalo/app/app_state.dart';
import 'package:encargalo/app/theme.dart';
import 'package:encargalo/core/domain/models.dart';
import 'package:encargalo/core/network/api_client.dart';
import 'package:encargalo/features/auth/presentation/auth_screens.dart';
import 'package:encargalo/features/home/domain/home_overview.dart';
import 'package:encargalo/features/home/presentation/home_shell.dart';
import 'package:encargalo/features/locations/presentation/location_selector.dart';
import 'package:encargalo/features/locations/data/peru_location_catalog.dart';
import 'package:encargalo/features/locations/domain/location_entry.dart';
import 'package:encargalo/features/marketplace/data/market_repository.dart';

class FixtureMarket extends MarketRepository {
  FixtureMarket()
    : super(
        ApiClient(
          baseUrl: 'https://fixture.invalid',
          publicKey: 'fixture',
          token: () async => null,
        ),
        SupabaseClient(
          'https://fixture.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  Future<HomeOverview> overview() async => HomeOverview.fromJson({
    'requests_count': 0,
    'quotes_count': 0,
    'orders_count': 0,
    'requests': [],
    'orders': [],
  });
}

class LoadedCatalog implements LocationCatalog {
  final List<LocationEntry> rows;
  LoadedCatalog(this.rows);
  @override
  Future<List<LocationEntry>> bundled() => SynchronousFuture(rows);
  @override
  Future<List<LocationEntry>> refresh(String region) =>
      SynchronousFuture(rows.where((e) => e.region == region).toList());
}

Future<void> loadPreviewFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'D:/desarrollo/flutter';
  for (final font
      in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
    final bytes =
        await File(
          '$root/bin/cache/artifacts/material_fonts/${font.value}',
        ).readAsBytes();
    await (FontLoader(font.key)
      ..addFont(SynchronousFuture(ByteData.sublistView(bytes)))).load();
  }
}

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    for (final business in [false, true]) {
      testWidgets(
        'Inicio ${business ? 'negocio' : 'cliente'}: ${width}px, texto 130%, datos fixture',
        (tester) async {
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            await tester.runAsync(loadPreviewFonts);
          }
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = await tester.runAsync(() async => FixtureMarket());
          final app =
              AppState()
                ..loading = false
                ..profile = Profile.fromJson({
                  'id': 'fixture',
                  'role': business ? 'negocio' : 'cliente',
                  'name': 'Cuenta de prueba de diseño',
                  'district': 'Castilla',
                  'description': '',
                  'categories': ['estampado'],
                })
                ..categories = [
                  Category.fromJson({'id': 'estampado', 'name': 'Estampado'}),
                  Category.fromJson({
                    'id': 'personalizados',
                    'name': 'Otros personalizados',
                  }),
                ]
                ..repository = repository;
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: app,
              child: MaterialApp(
                // Android resolves the default button family to Roboto. The
                // widget-test binding uses Ahem for explicit TextStyles, so
                // select the same Roboto locally for capture readability.
                theme: appTheme(Brightness.light).copyWith(
                  filledButtonTheme: FilledButtonThemeData(
                    style: appTheme(
                      Brightness.light,
                    ).filledButtonTheme.style?.copyWith(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.3)),
                      child: RepaintBoundary(
                        key: const ValueKey('design-capture'),
                        child: child!,
                      ),
                    ),
                home: const HomeScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Encárgalo'), findsOneWidget);
          if (const bool.fromEnvironment('CAPTURE_UI') && width == 360) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('design-capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(
                '../encargalo_documentacion/evidencias/vistas-fixture',
              );
              await directory.create(recursive: true);
              await File(
                '${directory.path}/inicio-${business ? 'negocio' : 'cliente'}-fixture.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          app.dispose();
          await tester.runAsync(() async => app.repository!.cloud.dispose());
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }
  testWidgets(
    'Alta separada usa datos de contacto y catálogo real, sin sesión ficticia',
    (tester) async {
      final locations = await tester.runAsync(
        () => PeruLocationCatalog().bundled(),
      );
      final app = AppState();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: appTheme(Brightness.dark),
            home: AuthScreen(
              initialRegister: true,
              locationCatalog: LoadedCatalog(locations!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Teléfono de contacto privado'), findsOneWidget);
      expect(find.byType(LocationSelector), findsOneWidget);
      expect(find.text('Confirmar contraseña'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
  testWidgets(
    'Ubigeo dependiente reinicia provincia y distrito al cambiar región',
    (tester) async {
      final locations = await tester.runAsync(
        () => PeruLocationCatalog().bundled(),
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationSelector(
              catalog: LoadedCatalog(locations!),
              onChanged: (value) => selected = value.code,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(selected, '200101');
      final region = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      region.onChanged!('Lima');
      await tester.pumpAndSettle();
      expect(selected!.startsWith('15'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

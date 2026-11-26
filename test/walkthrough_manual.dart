import 'package:encargalo/core/domain/models.dart';
import 'package:encargalo/features/marketplace/presentation/market_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/fake_backend.dart';

/// Recorrido funcional completo sobre las pantallas reales de la app.
///
/// Se ejecuta con `flutter test` (sin emulador ni claves) sobre un backend
/// Supabase simulado y SQLite en memoria. No reemplaza la verificación física
/// de cámara, GPS, push ni red móvil.
Future<void> main() async {
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Recorrido cliente: acceso, publicación y cierre de sesión', (
    tester,
  ) async {
    _surface(tester);
    final backend =
        FakeBackend()..addAccount(
          id: 'cliente-1',
          email: 'ana@fixture.invalid',
          name: 'Ana Cliente',
          district: 'Piura',
          categories: const ['estampado'],
        );
    final fixture = await AppFixture.create(backend);
    addTearDown(() => fixture.stop(tester));
    await fixture.pump(tester);

    expect(find.text('Qué gusto tenerte de vuelta'), findsOneWidget);
    await _write(
      tester,
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'ana@fixture.invalid',
    );
    await _write(
      tester,
      find.widgetWithText(TextFormField, 'Contraseña'),
      'clave-segura',
    );
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Crear mi solicitud'), findsOneWidget);

    await tester.tap(find.text('Crear mi solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('PASO 1 DE 4'), findsOneWidget);

    const title = 'Polos bordados para la promo';
    await _write(
      tester,
      find.widgetWithText(TextField, 'Título del producto'),
      title,
    );
    await _write(
      tester,
      find.widgetWithText(TextField, 'Especificaciones'),
      'Doce polos de algodón con bordado frontal y entrega coordinada.',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estampado').last);
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Continuar'));
    expect(find.text('PASO 2 DE 4'), findsOneWidget);

    await _tapVisible(tester, find.text('Continuar'));
    expect(find.text('PASO 3 DE 4'), findsOneWidget);
    await _write(
      tester,
      find.widgetWithText(TextField, 'Dirección o referencia manual'),
      'Frente a la plaza de armas, referencia celeste.',
    );

    await _tapVisible(tester, find.text('Continuar'));
    expect(find.text('PASO 4 DE 4'), findsOneWidget);
    expect(find.text(title), findsWidgets);

    await _tapVisible(tester, find.text('Publicar solicitud'));
    await _confirm(tester);

    expect(find.text('La nube confirmó la publicación.'), findsOneWidget);
    expect(backend.requests.single['title'], title);
    expect(backend.requests.single['status'], 'open');
    final drafts = await fixture.app.local!.drafts(fixture.app.owner!);
    expect(drafts.single.syncState, 'synced');
    expect(await fixture.app.local!.pending(fixture.app.owner!), isEmpty);

    await _openTab(tester, 'Solicitudes');
    final card = find.descendant(
      of: find.byType(RequestListScreen),
      matching: find.text(title),
    );
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Detalle de solicitud'), findsOneWidget);
    expect(find.text('Publicada'), findsWidgets);

    await _back(tester);
    await _openTab(tester, 'Perfil');
    await _tapVisible(tester, find.text('Cerrar sesión'));
    await _confirm(tester);

    expect(fixture.app.profile, isNull);
    expect(find.text('Ingresar'), findsOneWidget);
  });

  testWidgets('Recorrido negocio: cotizar una solicitud publicada', (
    tester,
  ) async {
    _surface(tester);
    final backend = FakeBackend();
    final client = backend.addAccount(
      id: 'cliente-1',
      email: 'ana@fixture.invalid',
      name: 'Ana Cliente',
    );
    backend.addAccount(
      id: 'negocio-1',
      email: 'taller@fixture.invalid',
      role: 'negocio',
      name: 'Taller Piura',
      categories: const ['estampado', 'bordado'],
    );
    final request = backend.addRequest(
      owner: client,
      id: 'req-1',
      title: 'Polos bordados para la promo',
    );
    final fixture = await AppFixture.create(backend);
    addTearDown(() => fixture.stop(tester));
    await fixture.signIn('taller@fixture.invalid');
    await fixture.pump(tester);

    expect(find.text('Ver oportunidades'), findsOneWidget);
    await tester.tap(find.text('Ver oportunidades'));
    await tester.pumpAndSettle();

    final card = find.descendant(
      of: find.byType(RequestListScreen),
      matching: find.text(request['title'] as String),
    );
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('Oportunidad'), findsOneWidget);
    await _tapVisible(tester, find.text('Cotizar este encargo'));
    expect(find.text('Tu propuesta'), findsOneWidget);

    await _write(
      tester,
      find.widgetWithText(TextFormField, 'Precio TOTAL en soles'),
      '250.00',
    );
    await _write(
      tester,
      find.widgetWithText(TextFormField, 'Adelanto para iniciar'),
      '50.00',
    );
    await _write(
      tester,
      find.widgetWithText(TextFormField, 'Condiciones del acuerdo'),
      'Incluye bordado, empaque y entrega coordinada.',
    );

    await _tapVisible(tester, find.text('Revisar y enviar cotización'));
    expect(find.text('Enviar propuesta'), findsOneWidget);
    await _confirm(tester);

    expect(
      find.text('La nube confirmó el envío de la cotización.'),
      findsOneWidget,
    );
    expect(backend.quotes.single['total_cents'], 25000);
    expect(backend.quotes.single['deposit_cents'], 5000);
    expect(backend.quotes.single['status'], 'sent');
    expect(await fixture.app.local!.pending(fixture.app.owner!), isEmpty);

    await _back(tester);
    await _openTab(tester, 'Cotizaciones');
    expect(find.text('S/ 250.00'), findsWidgets);
    expect(find.textContaining('Enviada'), findsWidgets);
  });

  testWidgets(
    'Recorrido acuerdo: aceptar, pagar adelanto y cancelar con devolución',
    (tester) async {
      _surface(tester);
      final backend = FakeBackend();
      final client = backend.addAccount(
        id: 'cliente-1',
        email: 'ana@fixture.invalid',
        name: 'Ana Cliente',
      );
      final business = backend.addAccount(
        id: 'negocio-1',
        email: 'taller@fixture.invalid',
        role: 'negocio',
        name: 'Taller Piura',
        categories: const ['estampado'],
      );
      final request = backend.addRequest(
        owner: client,
        id: 'req-1',
        title: 'Polos bordados para la promo',
      );
      backend.addQuote(request: request, business: business, id: 'quote-1');

      final fixture = await AppFixture.create(backend);
      addTearDown(() => fixture.stop(tester));
      await fixture.signIn('ana@fixture.invalid');
      await fixture.pump(tester);

      await _openTab(tester, 'Solicitudes');
      await tester.tap(
        find.descendant(
          of: find.byType(RequestListScreen),
          matching: find.text('Polos bordados para la promo'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Detalle de solicitud'), findsOneWidget);
      expect(find.text('S/ 250.00'), findsWidgets);
      await _tapVisible(tester, find.text('Aceptar cotización'));
      expect(find.text('Confirmar acuerdo'), findsOneWidget);
      await _confirm(tester);

      expect(find.text('Seguimiento del pedido'), findsOneWidget);
      expect(find.text('Confirmado'), findsWidgets);
      expect(find.text('Contacto del negocio'), findsOneWidget);

      await _tapVisible(tester, find.text('Registrar pago simulado'));
      expect(find.text('Importe de prueba'), findsOneWidget);
      await tester.tap(find.text('Confirmar simulación'));
      await tester.pumpAndSettle();

      expect(backend.orders.single['paid_cents'], 5000);
      expect(find.text('Pago · S/ 50.00'), findsOneWidget);

      await _tapVisible(tester, find.text('Cancelar pedido'));
      expect(find.text('Cancelar antes de producción'), findsOneWidget);
      await _write(
        tester,
        find.widgetWithText(TextFormField, 'Motivo y propuesta de solución'),
        'Ya no necesito el producto para la actividad.',
      );
      await tester.tap(find.text('Confirmar cancelación'));
      await tester.pumpAndSettle();

      expect(backend.orders.single['status'], 'cancelled');
      expect(backend.orders.single['paid_cents'], 0);
      expect(find.text('Cancelado'), findsWidgets);
      expect(find.text('Devolución · S/ 50.00'), findsOneWidget);
      expect(find.text('Cancelación: aceptada'), findsOneWidget);
    },
  );

  testWidgets('Recorrido pedido: producción, saldo final y entrega', (
    tester,
  ) async {
    _surface(tester);
    final backend = FakeBackend();
    final client = backend.addAccount(
      id: 'cliente-1',
      email: 'ana@fixture.invalid',
      name: 'Ana Cliente',
    );
    final business = backend.addAccount(
      id: 'negocio-1',
      email: 'taller@fixture.invalid',
      role: 'negocio',
      name: 'Taller Piura',
      categories: const ['estampado'],
    );
    final request = backend.addRequest(
      owner: client,
      id: 'req-1',
      title: 'Polos bordados para la promo',
    );
    backend.addOrder(
      request: request,
      client: client,
      business: business,
      id: 'order-1',
      paidCents: 5000,
    );
    final fixture = await AppFixture.create(backend);
    addTearDown(() => fixture.stop(tester));

    await fixture.signIn('taller@fixture.invalid');
    await fixture.pump(tester);
    await _openTab(tester, 'Pedidos');
    await tester.tap(
      find.descendant(
        of: find.byType(OrdersScreen),
        matching: find.text('Polos bordados para la promo'),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Marcar En producción'));
    await _confirm(tester);
    expect(backend.orders.single['status'], 'production');

    await _tapVisible(tester, find.text('Marcar Listo'));
    await _confirm(tester);
    expect(backend.orders.single['status'], 'ready');

    await fixture.app.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Ingresar'), findsOneWidget);

    await fixture.signIn('ana@fixture.invalid');
    await tester.pumpAndSettle();
    await _openTab(tester, 'Pedidos');
    await tester.tap(
      find.descendant(
        of: find.byType(OrdersScreen),
        matching: find.text('Polos bordados para la promo'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Listo'), findsWidgets);
    expect(find.textContaining('Completa el saldo simulado'), findsOneWidget);
    await _tapVisible(tester, find.text('Registrar pago simulado'));
    await tester.tap(find.text('Confirmar simulación'));
    await tester.pumpAndSettle();
    expect(find.text('Pago · S/ 200.00'), findsOneWidget);

    await _tapVisible(tester, find.text('Confirmar recepción y entrega'));
    await _confirm(tester);

    expect(backend.orders.single['status'], 'delivered');
    expect(find.text('Entregado'), findsWidgets);
    expect(
      backend.history.map((event) => event['new_status']),
      containsAll(<String>['confirmed', 'production', 'ready', 'delivered']),
    );
  });

  testWidgets('Publicación sin respuesta queda pendiente y se reintenta', (
    tester,
  ) async {
    _surface(tester);
    final backend = FakeBackend();
    backend.addAccount(
      id: 'cliente-1',
      email: 'ana@fixture.invalid',
      name: 'Ana Cliente',
    );
    final fixture = await AppFixture.create(backend);
    addTearDown(() => fixture.stop(tester));
    await fixture.signIn('ana@fixture.invalid');

    backend.failPublishes = true;
    final draft = RequestDraft(
      id: 'borrador-1',
      ownerId: 'cliente-1',
      title: 'Tazas personalizadas',
      detail: 'Diez tazas de cerámica con el logo impreso.',
      categoryId: 'estampado',
      district: 'Piura',
      quantity: 10,
      desiredDate: DateTime.now().add(const Duration(days: 12)),
      locationCode: '200101',
    );
    await fixture.app.local!.saveDraft(draft);
    await fixture.app.local!.enqueue(draft);
    await fixture.app.synchronize();

    final pending = await fixture.app.local!.pending('cliente-1');
    expect(pending, hasLength(1));
    expect(pending.single['attempts'], 1);

    await fixture.pump(tester);
    await tester.tap(find.byTooltip('Sincronización'));
    await tester.pumpAndSettle();
    expect(find.text('Publicación pendiente'), findsOneWidget);
    expect(
      find.textContaining('El servicio no está disponible'),
      findsOneWidget,
    );

    backend.failPublishes = false;
    await tester.tap(find.text('Intentar sincronizar'));
    await tester.pumpAndSettle();

    expect(find.text('No hay envíos pendientes'), findsOneWidget);
    expect(backend.requests.single['title'], 'Tazas personalizadas');
    final drafts = await fixture.app.local!.drafts('cliente-1');
    expect(drafts.single.syncState, 'synced');
  });
}

Future<void> _write(WidgetTester tester, Finder field, String value) async {
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text('Confirmar'),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

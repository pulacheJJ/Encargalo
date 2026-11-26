import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;

class _FakeFailure implements Exception {
  _FakeFailure(this.message, this.status);
  final String message;
  final int status;
}

/// Backend Supabase simulado para las pruebas de integración.
///
/// Conserva el mismo contrato HTTP que usa la app (Auth, PostgREST y RPC) para
/// que el recorrido se ejecute sobre las pantallas reales sin cuentas, red ni
/// secretos. No sustituye las pruebas contra el proyecto cloud real: cámara,
/// GPS, push y latencia se siguen verificando en un Android físico.
class FakeBackend {
  FakeBackend() {
    client = MockClient(_handle);
  }

  late final MockClient client;
  final _uuid = const Uuid();

  final Map<String, FakeAccount> accounts = <String, FakeAccount>{};
  final Map<String, String> _emailIndex = <String, String>{};
  final Map<String, Json> contacts = <String, Json>{};
  final List<Json> requests = <Json>[];
  final List<Json> quotes = <Json>[];
  final List<Json> orders = <Json>[];
  final List<Json> payments = <Json>[];
  final List<Json> cancellations = <Json>[];
  final List<Json> notifications = <Json>[];
  final List<Json> history = <Json>[];
  final List<Json> deliveries = <Json>[];

  static const categories = <Json>[
    {'id': 'estampado', 'name': 'Estampado'},
    {'id': 'bordado', 'name': 'Bordado'},
    {'id': 'personalizados', 'name': 'Otros personalizados'},
  ];

  String? sessionUserId;

  /// Permite reproducir una publicación sin respuesta del servidor.
  bool failPublishes = false;

  FakeAccount? get current =>
      sessionUserId == null ? null : accounts[sessionUserId];

  String passwordFor(String email) =>
      _accountByEmail(email)?.password ?? 'clave-segura';

  FakeAccount addAccount({
    required String id,
    required String email,
    String password = 'clave-segura',
    String role = 'cliente',
    String name = 'Cuenta de prueba',
    String district = 'Piura',
    String description = '',
    List<String> categories = const ['estampado'],
    String phone = '999 999 999',
  }) {
    final account = FakeAccount(
      id: id,
      email: email,
      password: password,
      role: role,
      name: name,
      district: district,
      description: description,
      categories: categories,
    );
    accounts[id] = account;
    _emailIndex[email] = id;
    contacts[id] = {
      'owner_id': id,
      'phone': phone,
      'contact_name': name,
      'address_reference': '',
    };
    return account;
  }

  Json addRequest({
    required FakeAccount owner,
    required String id,
    String title = 'Polos para una actividad',
    String detail = 'Polos de algodón con estampado frontal y acabado simple.',
    String categoryId = 'estampado',
    String district = 'Piura',
    int quantity = 12,
    String status = 'open',
    int version = 1,
    DateTime? desiredDate,
    String locationCode = '200101',
  }) {
    final row = <String, dynamic>{
      'id': id,
      'owner_id': owner.id,
      'title': title,
      'detail': detail,
      'category_id': categoryId,
      'district': district,
      'quantity': quantity,
      'status': status,
      'version': version,
      'quote_count': 0,
      'desired_date': _date(
        desiredDate ?? DateTime.now().add(const Duration(days: 21)),
      ),
      'location_code': locationCode,
      'specifications': <String, dynamic>{},
      'created_at': _now(),
      'request_photos': <Json>[],
    };
    requests.add(row);
    return row;
  }

  Json addQuote({
    required Json request,
    required FakeAccount business,
    String? id,
    int totalCents = 25000,
    int depositCents = 5000,
    String conditions = 'Incluye materiales, bordado y empaque.',
    String status = 'sent',
    int version = 1,
    DateTime? promisedDate,
    DateTime? expiresAt,
  }) {
    final row = <String, dynamic>{
      'id': id ?? 'quote-${_uuid.v4()}',
      'request_id': request['id'],
      'business_id': business.id,
      'total_cents': totalCents,
      'deposit_cents': depositCents,
      'quantity': request['quantity'],
      'conditions': conditions,
      'promised_date': _date(
        promisedDate ?? DateTime.now().add(const Duration(days: 10)),
      ),
      'expires_at':
          (expiresAt ?? DateTime.now().add(const Duration(days: 5)))
              .toUtc()
              .toIso8601String(),
      'status': status,
      'version': version,
      'created_at': _now(),
    };
    quotes.add(row);
    request['quote_count'] = ((request['quote_count'] as int?) ?? 0) + 1;
    return row;
  }

  Json addOrder({
    required Json request,
    required FakeAccount client,
    required FakeAccount business,
    String? quoteId,
    String? id,
    int totalCents = 25000,
    int depositCents = 5000,
    int paidCents = 0,
    String status = 'confirmed',
    int version = 1,
    DateTime? promisedDate,
  }) {
    final row = <String, dynamic>{
      'id': id ?? 'order-${_uuid.v4()}',
      'request_id': request['id'],
      'quote_id': quoteId ?? 'quote-${_uuid.v4()}',
      'client_id': client.id,
      'business_id': business.id,
      'business_name': business.name,
      'title': request['title'],
      'conditions': 'Incluye materiales, bordado y empaque.',
      'status': status,
      'total_cents': totalCents,
      'quantity': request['quantity'],
      'version': version,
      'promised_date': _date(
        promisedDate ?? DateTime.now().add(const Duration(days: 10)),
      ),
      'deposit_cents': depositCents,
      'paid_cents': paidCents,
      'payments_required': true,
      'created_at': _now(),
      'updated_at': _now(),
    };
    orders.add(row);
    history.add({
      'id': _uuid.v4(),
      'order_id': row['id'],
      'actor_id': client.id,
      'previous_status': null,
      'new_status': 'confirmed',
      'created_at': _now(),
    });
    return row;
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    try {
      if (path.startsWith('/auth/v1/')) {
        return _auth(request, path.substring('/auth/v1/'.length));
      }
      if (path.startsWith('/rest/v1/rpc/')) {
        return _rpc(request, path.substring('/rest/v1/rpc/'.length));
      }
      if (path.startsWith('/rest/v1/')) {
        return _select(
          path.substring('/rest/v1/'.length),
          request.url.queryParameters,
        );
      }
      return _json({'message': 'Ruta no simulada: $path'}, 404);
    } on _FakeFailure catch (e) {
      return _json({'message': e.message}, e.status);
    }
  }

  http.Response _auth(http.Request request, String action) {
    if (action == 'token') {
      final body = _body(request);
      final grant = request.url.queryParameters['grant_type'];
      if (grant == 'refresh_token') {
        final account = current;
        if (account == null) throw _FakeFailure('Sesión ausente', 400);
        return _json(_session(account));
      }
      final account = _accountByEmail(body['email'] as String?);
      if (account == null || account.password != body['password']) {
        return _json({
          'error': 'invalid_grant',
          'error_description': 'Invalid login credentials',
          'error_code': 'invalid_credentials',
        }, 400);
      }
      sessionUserId = account.id;
      return _json(_session(account));
    }
    if (action == 'logout') {
      sessionUserId = null;
      return http.Response('', 204);
    }
    if (action == 'user') {
      final account = current;
      if (account == null) return _json({'message': 'Sesión ausente'}, 401);
      return _json(_user(account));
    }
    return _json({'message': 'Auth no simulada: $action'}, 404);
  }

  http.Response _select(String table, Map<String, String> query) {
    var rows = switch (table) {
      'profiles' => accounts.values.map((account) => account.profile).toList(),
      'categories' => categories,
      'requests' => requests,
      'quotes' => quotes,
      'orders' => orders,
      'order_history' => history,
      'order_payments' => payments,
      'order_cancellations' => cancellations,
      'notifications' => notifications,
      'profile_contacts' => contacts.values.toList(),
      'request_delivery' => deliveries,
      'locations' => <Json>[],
      _ => <Json>[],
    };
    final me = current;
    // RLS del feed: un negocio no ve sus propias solicitudes ni categorías ajenas.
    if (table == 'requests' &&
        me != null &&
        me.role == 'negocio' &&
        !query.containsKey('owner_id')) {
      rows =
          rows
              .where(
                (row) =>
                    row['owner_id'] != me.id &&
                    me.categories.contains(row['category_id']),
              )
              .toList();
    }
    rows = rows.where((row) => _matches(row, query)).toList();
    if (table == 'requests') {
      rows.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    }
    if (const {'order_payments', 'order_cancellations'}.contains(table)) {
      rows.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    }
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    final limit = int.tryParse(query['limit'] ?? '');
    if (offset > 0) rows = rows.skip(offset).toList();
    if (limit != null) rows = rows.take(limit).toList();
    return _json(rows);
  }

  http.Response _rpc(http.Request request, String name) {
    final args = _body(request);
    final me = current;
    if (me == null) throw _FakeFailure('Sesión requerida', 401);
    switch (name) {
      case 'home_overview':
        return _json(_overview(me));
      case 'publish_request':
      case 'publish_request_v2':
        return _json(_publish(me, args));
      case 'submit_quote':
        return _json(_submitQuote(me, args));
      case 'accept_quote':
        return _json(_acceptQuote(me, args));
      case 'transition_order':
        return _json(_transition(me, args));
      case 'simulate_order_payment':
        return _json(_pay(me, args));
      case 'request_order_cancellation':
        return _json(_requestCancellation(me, args));
      case 'resolve_order_cancellation':
        return _json(_resolveCancellation(me, args));
      case 'order_contact':
        return _json(_orderContact(me, args));
      case 'delete_request':
        _deleteRequest(me, args);
        return _json(<String, dynamic>{});
      case 'mark_notification_read':
      case 'save_profile_details':
        return _json(<String, dynamic>{});
      default:
        throw _FakeFailure('RPC no simulada: $name', 404);
    }
  }

  Json _publish(FakeAccount me, Json args) {
    if (failPublishes) {
      throw _FakeFailure(
        'El servicio no está disponible (fallo simulado).',
        503,
      );
    }
    final data = Map<String, dynamic>.from(args['p_data'] as Map);
    final id = data['id'] as String;
    final index = requests.indexWhere((row) => row['id'] == id);
    if (index >= 0 && requests[index]['owner_id'] != me.id) {
      throw _FakeFailure('Sin autorización', 403);
    }
    final previous = index >= 0 ? requests[index] : null;
    final row = <String, dynamic>{
      'id': id,
      'owner_id': me.id,
      'title': data['title'],
      'detail': data['detail'],
      'category_id': data['category_id'],
      'district': data['district'],
      'quantity': data['quantity'],
      'status': 'open',
      'version': previous == null ? 1 : (previous['version'] as int) + 1,
      'quote_count': previous?['quote_count'] ?? 0,
      'desired_date': data['desired_date'],
      'location_code': data['location_code'],
      'specifications': data['specifications'] ?? <String, dynamic>{},
      'created_at': previous?['created_at'] ?? _now(),
      'request_photos': <Json>[],
    };
    if (index >= 0) {
      requests[index] = row;
    } else {
      requests.add(row);
    }
    final delivery = data['delivery'];
    if (delivery is Map) {
      deliveries.removeWhere((row) => row['request_id'] == id);
      deliveries.add({
        'request_id': id,
        ...Map<String, dynamic>.from(delivery),
      });
    }
    return row;
  }

  Json _submitQuote(FakeAccount me, Json args) {
    final data = Map<String, dynamic>.from(args['p_data'] as Map);
    final requestRow = _firstOrThrow(
      requests,
      (row) => row['id'] == data['request_id'],
      'Solicitud no disponible',
    );
    final index = quotes.indexWhere(
      (row) =>
          row['request_id'] == requestRow['id'] && row['business_id'] == me.id,
    );
    final previous = index >= 0 ? quotes[index] : null;
    final row = <String, dynamic>{
      'id': data['id'] ?? previous?['id'] ?? 'quote-${_uuid.v4()}',
      'request_id': requestRow['id'],
      'business_id': me.id,
      'total_cents': data['total_cents'],
      'deposit_cents': data['deposit_cents'] ?? 0,
      'quantity': requestRow['quantity'],
      'conditions': data['conditions'],
      'promised_date': data['promised_date'],
      'expires_at': data['expires_at'],
      'status': 'sent',
      'version': previous == null ? 1 : (previous['version'] as int) + 1,
      'created_at': previous?['created_at'] ?? _now(),
    };
    if (index >= 0) {
      quotes[index] = row;
    } else {
      quotes.add(row);
      requestRow['quote_count'] =
          ((requestRow['quote_count'] as int?) ?? 0) + 1;
    }
    return row;
  }

  Json _acceptQuote(FakeAccount me, Json args) {
    final quote = _firstOrThrow(
      quotes,
      (row) => row['id'] == args['p_quote'],
      'Cotización no disponible',
    );
    final requestRow = _firstOrThrow(
      requests,
      (row) => row['id'] == quote['request_id'],
      'Solicitud no disponible',
    );
    if (requestRow['owner_id'] != me.id) {
      throw _FakeFailure('Sin autorización', 403);
    }
    final business = accounts[quote['business_id']]!;
    final order = addOrder(
      request: requestRow,
      client: me,
      business: business,
      quoteId: quote['id'] as String,
      totalCents: (quote['total_cents'] as num).toInt(),
      depositCents: (quote['deposit_cents'] as num?)?.toInt() ?? 0,
      promisedDate: DateTime.parse(quote['promised_date'] as String),
    );
    requestRow['status'] = 'awarded';
    requestRow['version'] = (requestRow['version'] as int) + 1;
    for (final row in quotes.where(
      (q) => q['request_id'] == requestRow['id'],
    )) {
      row['status'] = row['id'] == quote['id'] ? 'accepted' : 'not_selected';
    }
    return order;
  }

  Json _transition(FakeAccount me, Json args) {
    final order = _firstOrThrow(
      orders,
      (row) => row['id'] == args['p_order'],
      'Pedido no disponible',
    );
    final next = args['p_status'] as String;
    if (!(order['client_id'] == me.id || order['business_id'] == me.id)) {
      throw _FakeFailure('Sin autorización', 403);
    }
    history.add({
      'id': _uuid.v4(),
      'order_id': order['id'],
      'actor_id': me.id,
      'previous_status': order['status'],
      'new_status': next,
      'created_at': _now(),
    });
    order['status'] = next;
    order['version'] = (order['version'] as int) + 1;
    order['updated_at'] = _now();
    return order;
  }

  Json _pay(FakeAccount me, Json args) {
    final order = _firstOrThrow(
      orders,
      (row) => row['id'] == args['p_order'],
      'Pedido no disponible',
    );
    final approved = args['p_approved'] == true;
    final amount = (args['p_amount'] as num).toInt();
    final entry = <String, dynamic>{
      'id': _uuid.v4(),
      'order_id': order['id'],
      'actor_id': me.id,
      'kind': 'payment',
      'amount_cents': amount,
      'status': approved ? 'approved' : 'declined',
      'created_at': _now(),
    };
    payments.insert(0, entry);
    if (approved) {
      order['paid_cents'] = (order['paid_cents'] as int) + amount;
      order['version'] = (order['version'] as int) + 1;
      order['updated_at'] = _now();
    }
    return entry;
  }

  Json _requestCancellation(FakeAccount me, Json args) {
    final order = _firstOrThrow(
      orders,
      (row) => row['id'] == args['p_order'],
      'Pedido no disponible',
    );
    final retained = (args['p_retained'] as num?)?.toInt() ?? 0;
    final immediate = order['status'] == 'confirmed';
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'order_id': order['id'],
      'requested_by': me.id,
      'reason': (args['p_reason'] as String).trim(),
      'retained_cents': retained,
      'status': immediate ? 'accepted' : 'pending',
      'resolved_by': immediate ? me.id : null,
      'resolved_at': immediate ? _now() : null,
      'created_at': _now(),
    };
    cancellations.insert(0, row);
    if (immediate) _applyCancellation(order, row, me);
    return row;
  }

  Json _resolveCancellation(FakeAccount me, Json args) {
    final row = _firstOrThrow(
      cancellations,
      (cancellation) => cancellation['id'] == args['p_cancellation'],
      'Cancelación no disponible',
    );
    final decision = args['p_decision'] as String;
    row['status'] = decision;
    row['resolved_by'] = me.id;
    row['resolved_at'] = _now();
    final order = _firstOrThrow(
      orders,
      (order) => order['id'] == row['order_id'],
      'Pedido no disponible',
    );
    if (decision == 'accepted') _applyCancellation(order, row, me);
    return row;
  }

  void _applyCancellation(Json order, Json cancellation, FakeAccount actor) {
    final refund =
        (order['paid_cents'] as int) - (cancellation['retained_cents'] as int);
    if (refund > 0) {
      payments.insert(0, {
        'id': _uuid.v4(),
        'order_id': order['id'],
        'actor_id': actor.id,
        'kind': 'refund',
        'amount_cents': refund,
        'status': 'approved',
        'created_at': _now(),
      });
    }
    order['paid_cents'] = cancellation['retained_cents'];
    order['status'] = 'cancelled';
    order['version'] = (order['version'] as int) + 1;
    order['updated_at'] = _now();
  }

  Json _orderContact(FakeAccount me, Json args) {
    final order = _firstOrThrow(
      orders,
      (row) => row['id'] == args['p_order'],
      'Pedido no disponible',
    );
    final other =
        order['client_id'] == me.id
            ? order['business_id'] as String
            : order['client_id'] as String;
    final account = accounts[other];
    final contact = contacts[other] ?? <String, dynamic>{};
    return {
      'contact_name': contact['contact_name'] ?? account?.name ?? '',
      'phone': contact['phone'] ?? '',
    };
  }

  void _deleteRequest(FakeAccount me, Json args) {
    final row = _firstOrThrow(
      requests,
      (request) => request['id'] == args['p_id'],
      'Solicitud no disponible',
    );
    if (row['owner_id'] != me.id) throw _FakeFailure('Sin autorización', 403);
    if (row['status'] == 'deleted') return;
    row['status'] = 'deleted';
    row['version'] = (row['version'] as int) + 1;
    for (final quote in quotes.where((q) => q['request_id'] == row['id'])) {
      quote['status'] = 'not_selected';
    }
  }

  Json _overview(FakeAccount me) {
    bool visible(Json row) =>
        row['status'] == 'open' &&
        (row['owner_id'] == me.id ||
            (me.role == 'negocio' &&
                row['owner_id'] != me.id &&
                me.categories.contains(row['category_id'])));
    final openRequests = requests.where(visible).toList();
    final relatedOrders =
        orders
            .where(
              (row) => row['client_id'] == me.id || row['business_id'] == me.id,
            )
            .toList();
    final activeOrders =
        relatedOrders
            .where((row) => !['delivered', 'cancelled'].contains(row['status']))
            .toList();
    final sentQuotes =
        quotes.where((quote) {
          final request = requests.firstWhere(
            (row) => row['id'] == quote['request_id'],
            orElse: () => <String, dynamic>{},
          );
          if (quote['status'] != 'sent' || request['status'] != 'open') {
            return false;
          }
          return me.role == 'negocio'
              ? quote['business_id'] == me.id
              : request['owner_id'] == me.id;
        }).length;
    return {
      'requests_count': openRequests.length,
      'quotes_count': sentQuotes,
      'orders_count': activeOrders.length,
      'requests': openRequests.take(3).toList(),
      'orders': activeOrders.take(3).toList(),
    };
  }

  FakeAccount? _accountByEmail(String? email) {
    final id = email == null ? null : _emailIndex[email];
    return id == null ? null : accounts[id];
  }

  Json _session(FakeAccount account) => {
    'access_token': _token(account),
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
    'refresh_token': 'refresh-${account.id}',
    'user': _user(account),
  };

  Json _user(FakeAccount account) => {
    'id': account.id,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': account.email,
    'email_confirmed_at': '2026-01-01T00:00:00Z',
    'app_metadata': {
      'provider': 'email',
      'providers': ['email'],
    },
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };

  String _token(FakeAccount account) {
    final header = _segment({'alg': 'HS256', 'typ': 'JWT'});
    final payload = _segment({
      'sub': account.id,
      'role': 'authenticated',
      'aud': 'authenticated',
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });
    return '$header.$payload.fixture';
  }

  String _segment(Json data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');

  Json _body(http.Request request) {
    if (request.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(request.body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'value': decoded};
  }

  bool _matches(Json row, Map<String, String> query) {
    for (final entry in query.entries) {
      if (const {
        'select',
        'order',
        'limit',
        'offset',
        'on_conflict',
      }.contains(entry.key)) {
        continue;
      }
      final expected = entry.value;
      final actual = '${row[entry.key] ?? ''}';
      if (expected.startsWith('eq.')) {
        if (actual != expected.substring(3)) return false;
      } else if (expected.startsWith('neq.')) {
        if (actual == expected.substring(4)) return false;
      } else if (expected.startsWith('ilike.')) {
        final needle = expected.substring(6).replaceAll('*', '').toLowerCase();
        if (!actual.toLowerCase().contains(needle)) return false;
      }
    }
    return true;
  }

  Json _firstOrThrow(
    List<Json> rows,
    bool Function(Json) predicate,
    String message,
  ) {
    for (final row in rows) {
      if (predicate(row)) return row;
    }
    throw _FakeFailure(message, 404);
  }

  http.Response _json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  String _now() => DateTime.now().toUtc().toIso8601String();

  String _date(DateTime date) =>
      date.toUtc().toIso8601String().substring(0, 10);
}

class FakeAccount {
  FakeAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.role,
    required this.name,
    required this.district,
    required this.description,
    required this.categories,
  });

  final String id, email, password, role, name, district, description;
  final List<String> categories;

  Json get profile => {
    'id': id,
    'role': role,
    'name': name,
    'district': district,
    'description': description,
    'categories': categories,
    'location_code': '200101',
    'business_address': 'Av. Principal 123, Piura',
    'business_hours': 'Lunes a sábado, 9:00 a 18:00',
    'website': 'https://negocio.ejemplo',
  };
}

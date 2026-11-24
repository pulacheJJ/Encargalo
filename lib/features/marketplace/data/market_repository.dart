import 'dart:io';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/domain/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/query_cache.dart';
import '../../home/domain/home_overview.dart';

class MarketRepository {
  final ApiClient api;
  final SupabaseClient cloud;
  MarketRepository(this.api, this.cloud);
  final _queries = QueryCache();
  void invalidate() => _queries.invalidate();
  Future<List<Json>> _select(String table, {Json? query}) => _queries.get(
    '$userId:$table:${jsonEncode(query)}',
    () => api.select(table, query: query),
  );
  Future<HomeOverview> overview() => _queries.get(
    '$userId:home',
    () async => HomeOverview.fromJson(await api.rpcRecord('home_overview', {})),
  );
  Future<void> _assertAccount(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (cloud.auth.currentUser?.id != owner ||
        prefs.getString('active_user') != owner) {
      throw ApiFailure(
        'La cuenta cambió o cerró sesión. Se detuvo el envío anterior.',
        status: 401,
      );
    }
  }

  String get userId => cloud.auth.currentUser!.id;
  Future<Profile> profile([String? id]) async => Profile.fromJson(
    (await _select(
      'profiles',
      query: {'id': 'eq.${id ?? userId}', 'limit': 1},
    )).single,
  );
  Future<List<Category>> categories() => _queries.get(
    'categories',
    () async =>
        (await api.select(
          'categories',
          query: {'order': 'name.asc'},
        )).map(Category.fromJson).toList(),
    ttl: const Duration(hours: 1),
  );
  Future<List<RequestItem>> requests({
    required bool business,
    String search = '',
    String? category,
    String? status,
    String? district,
    int offset = 0,
  }) async {
    final rows = await _select(
      'requests',
      query: {
        'select': '*,request_photos(*)',
        'order': 'created_at.desc,id.desc',
        'limit': 30,
        'offset': offset,
        if (!business) 'owner_id': 'eq.$userId',
        if (business) 'status': 'eq.open',
        if (!business && status != null) 'status': 'eq.$status',
        if (category != null) 'category_id': 'eq.$category',
        if (district != null && district.isNotEmpty) 'district': 'eq.$district',
        if (search.isNotEmpty)
          'title': 'ilike.*${search.replaceAll(RegExp(r'[%*_,()]'), '')}*',
      },
    );
    return rows.map(RequestItem.fromJson).toList();
  }

  Future<RequestItem> request(String id) async {
    final rows = await _select(
      'requests',
      query: {'id': 'eq.$id', 'select': '*,request_photos(*)', 'limit': 1},
    );
    if (rows.isEmpty) {
      throw ApiFailure(
        'La solicitud no está disponible o no tiene permiso.',
        status: 404,
      );
    }
    return RequestItem.fromJson(rows.single);
  }

  Future<Delivery?> delivery(String id) async {
    final rows = await _select(
      'request_delivery',
      query: {'request_id': 'eq.$id', 'limit': 1},
    );
    return rows.isEmpty ? null : Delivery.fromJson(rows.single);
  }

  Future<List<Quote>> quotes({String? request, int offset = 0}) async =>
      (await _select(
        'quotes',
        query: {
          if (request != null) 'request_id': 'eq.$request',
          if (request == null) 'business_id': 'eq.$userId',
          'order': 'created_at.desc,id.desc',
          'limit': 30,
          'offset': offset,
        },
      )).map(Quote.fromJson).toList();
  Future<List<OrderItem>> orders({
    required bool business,
    String? status,
    int offset = 0,
  }) async =>
      (await _select(
        'orders',
        query: {
          business ? 'business_id' : 'client_id': 'eq.$userId',
          if (status != null) 'status': 'eq.$status',
          'order': 'promised_date.asc,id.asc',
          'limit': 30,
          'offset': offset,
        },
      )).map(OrderItem.fromJson).toList();
  Future<OrderItem> order(String id) async {
    final rows = await _select('orders', query: {'id': 'eq.$id', 'limit': 1});
    if (rows.isEmpty) {
      throw ApiFailure(
        'Pedido no disponible o acceso no autorizado.',
        status: 404,
      );
    }
    return OrderItem.fromJson(rows.single);
  }

  Future<List<Json>> history(String order) => api.select(
    'order_history',
    query: {'order_id': 'eq.$order', 'order': 'created_at.asc', 'limit': 10},
  );
  Future<List<Notice>> notifications({int offset = 0}) async =>
      (await api.select(
        'notifications',
        query: {
          'recipient_id': 'eq.$userId',
          'order': 'created_at.desc,id.desc',
          'limit': 30,
          'offset': offset,
        },
      )).map(Notice.fromJson).toList();
  Future<String> imageUrl(Photo p) =>
      cloud.storage.from('references').createSignedUrl(p.objectPath!, 300);
  Future<void> upload(Photo photo, String owner, String request) async {
    await _assertAccount(owner);
    final path = '$owner/$request/${photo.id}.jpg';
    if (photo.objectPath != null) return;
    if (photo.localPath == null || !await File(photo.localPath!).exists()) {
      throw ApiFailure(
        'Falta una foto del borrador. Recupérela o reemplácela.',
      );
    }
    try {
      await cloud.storage
          .from('references')
          .upload(
            path,
            File(photo.localPath!),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      // Una subida confirmada cuya respuesta se perdió se recupera sin sobreescribirla.
      if (e.statusCode != '409' &&
          e.statusCode != '400' &&
          e.error != 'Duplicate') {
        rethrow;
      }
      final object = await cloud.storage.from('references').info(path);
      if ((object.size ?? object.metadata?['size']) != photo.bytes) {
        throw ApiFailure(
          'La foto remota no coincide. Se conservará la copia local.',
        );
      }
    }
    photo.objectPath = path;
  }

  Future<int> publish(RequestDraft d, String op) async {
    await _assertAccount(d.ownerId);
    final error = d.validate();
    if (error != null) throw ApiFailure(error);
    for (final p in d.photos) {
      await upload(p, d.ownerId, d.id);
    }
    await _assertAccount(d.ownerId);
    final r = await api.rpcRecord(
      d.locationCode == null ? 'publish_request' : 'publish_request_v2',
      {
        'p_data': d.toRemote(),
        'p_operation': op,
        'p_expected_version': d.remoteVersion,
      },
      expectedSubject: d.ownerId,
    );
    return r['version'] as int;
  }

  Future<void> deleteRequest(RequestDraft d, String op) async {
    await _assertAccount(d.ownerId);
    await api.rpc('delete_request', {
      'p_id': d.id,
      'p_operation': op,
      'p_expected_version': d.remoteVersion,
    }, expectedSubject: d.ownerId);
  }

  Future<OrderItem> accept(String quote, String op) async => OrderItem.fromJson(
    await api.rpcRecord('accept_quote', {'p_quote': quote, 'p_operation': op}),
  );
  Future<void> transition(OrderItem o, String status, String op) =>
      api.rpc('transition_order', {
        'p_order': o.id,
        'p_status': status,
        'p_operation': op,
        'p_expected_version': o.version,
      });
  Future<Quote> submitQuote(
    Json data,
    String op,
    int version, {
    String? owner,
  }) async {
    final actor = owner ?? userId;
    await _assertAccount(actor);
    return Quote.fromJson(
      await api.rpcRecord('submit_quote', {
        'p_data': data,
        'p_operation': op,
        'p_expected_version': version,
      }, expectedSubject: actor),
    );
  }
}

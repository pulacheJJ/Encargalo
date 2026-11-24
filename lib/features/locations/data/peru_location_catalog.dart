import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../app/config.dart';
import '../../../core/network/query_cache.dart';
import '../domain/location_entry.dart';

class PeruLocationCatalog implements LocationCatalog {
  final http.Client client;
  final _cache = QueryCache();
  static Future<List<LocationEntry>>? _bundled;
  PeruLocationCatalog({http.Client? client}) : client = client ?? http.Client();
  @override
  Future<List<LocationEntry>> bundled() => _bundled ??= _readAsset();
  Future<List<LocationEntry>> _readAsset() async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/locations/peru.json'),
    );
    return List<LocationEntry>.unmodifiable(
      (data['locations'] as List).map(
        (e) => LocationEntry.fromJson(Map<String, dynamic>.from(e)),
      ),
    );
  }

  @override
  Future<List<LocationEntry>> refresh(
    String region,
  ) => _cache.get(region, () async {
    final uri = Uri.parse('${AppConfig.supabaseUrl}/rest/v1/locations').replace(
      queryParameters: {
        'region': 'eq.$region',
        'select': 'code,region,province,district',
        'order': 'province.asc,district.asc',
        'limit': '1000',
      },
    );
    final response = await client
        .get(uri, headers: {'apikey': AppConfig.supabaseKey})
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw const FormatException('No se pudo actualizar el catálogo');
    }
    final rows =
        (jsonDecode(utf8.decode(response.bodyBytes)) as List)
            .map((e) => LocationEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
    if (rows.isEmpty) {
      throw const FormatException('Catálogo remoto aún no disponible');
    }
    return rows;
  }, ttl: const Duration(days: 1));
  void dispose() => client.close();
}

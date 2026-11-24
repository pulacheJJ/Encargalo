import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

class ApiFailure implements Exception {
  final String message;
  final int? status;
  final bool retryable;
  ApiFailure(this.message, {this.status, this.retryable = false});
  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl, publicKey;
  final Future<String?> Function() token;
  final http.Client client;
  final Duration timeout;
  ApiClient({
    required this.baseUrl,
    required this.publicKey,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : client = client ?? http.Client();
  Future<dynamic> send(
    String method,
    String path, {
    Json? query,
    dynamic body,
    String? expectedSubject,
  }) async {
    String? jwt;
    try {
      jwt = await token().timeout(
        timeout < const Duration(seconds: 12)
            ? timeout
            : const Duration(seconds: 12),
      );
    } on TimeoutException {
      throw ApiFailure(
        'No se pudo renovar la sesión a tiempo. Revisa Internet y reintenta; tus borradores se conservan.',
        retryable: true,
      );
    }
    if (jwt != null && expectedSubject != null) {
      String? subject;
      try {
        final payload = jwt.split('.')[1];
        subject =
            (jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(payload))),
                )
                as Json)['sub'];
      } catch (_) {
        /* Un JWT inválido nunca autoriza esta operación. */
      }
      if (subject != expectedSubject) {
        throw ApiFailure(
          'La cuenta cambió. La operación anterior permanece pendiente.',
          status: 401,
        );
      }
    }
    if (jwt == null) {
      throw ApiFailure(
        'La sesión expiró. Vuelva a iniciar sesión.',
        status: 401,
      );
    }
    final uri = Uri.parse(
      '$baseUrl/$path',
    ).replace(queryParameters: query?.map((k, v) => MapEntry(k, v.toString())));
    final req = http.Request(method, uri)
      ..headers.addAll({
        'apikey': publicKey,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final response = await (() async {
        return http.Response.fromStream(await client.send(req));
      })().timeout(
        req.method == 'GET' && timeout > const Duration(seconds: 12)
            ? const Duration(seconds: 12)
            : timeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? server;
        String? serverCode;
        try {
          final data = jsonDecode(response.body);
          server = data['message'] ?? data['error'];
          serverCode = data['code'];
        } catch (_) {
          /* No mostrar HTML ni cabeceras. */
        }
        throw ApiFailure(
          switch (response.statusCode) {
            401 => 'La sesión expiró. Inicie sesión de nuevo.',
            403 => 'No tiene permiso para esta operación.',
            404 => 'El elemento ya no está disponible.',
            409 =>
              serverCode == 'PT409' && server != null && server.length <= 300
                  ? server
                  : 'Los datos cambiaron en otro dispositivo. Recargue antes de continuar.',
            429 => 'Se alcanzó el límite temporal. Inténtelo más tarde.',
            >= 500 =>
              'El servicio no está disponible. Los cambios pendientes se conservarán.',
            _ =>
              (serverCode == '23514'
                      ? 'Revisa los importes, fechas y límites del formulario.'
                      : server) ??
                  'No se pudo completar la operación (${response.statusCode}).',
          },
          status: response.statusCode,
          retryable: response.statusCode == 429 || response.statusCode >= 500,
        );
      }
      if (response.body.trim().isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiFailure(
          'El servidor devolvió datos no válidos.',
          retryable: true,
        );
      }
    } on TimeoutException {
      throw ApiFailure(
        'El servidor tardó demasiado. Puede reintentar.',
        retryable: true,
      );
    } on SocketException {
      throw ApiFailure(
        'No se pudo conectar. Sus borradores siguen guardados.',
        retryable: true,
      );
    } on http.ClientException {
      throw ApiFailure('No hay conexión con el servicio.', retryable: true);
    }
  }

  Future<List<Json>> select(String table, {Json? query}) async {
    final value = await send('GET', 'rest/v1/$table', query: query);
    if (value is! List || value.any((item) => item is! Map)) {
      throw ApiFailure(
        'La respuesta no tiene la estructura esperada.',
        retryable: true,
      );
    }
    return value.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<dynamic> rpc(String name, Json args, {String? expectedSubject}) =>
      send(
        'POST',
        'rest/v1/rpc/$name',
        body: args,
        expectedSubject: expectedSubject,
      );
  Future<Json> rpcRecord(
    String name,
    Json args, {
    String? expectedSubject,
  }) async {
    final raw = await rpc(name, args, expectedSubject: expectedSubject);
    final value = raw is List && raw.length == 1 ? raw.single : raw;
    if (value is! Map) {
      throw ApiFailure(
        'La operación no devolvió una confirmación válida.',
        retryable: true,
      );
    }
    return Map<String, dynamic>.from(value);
  }

  void close() => client.close();
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:encargalo/core/network/api_client.dart';

void main() {
  test(
    'Confirmación RPC admite registro o colección de un registro y rechaza una forma ambigua',
    () async {
      for (final body in ['{"version":1}', '[{"version":1}]']) {
        final client = ApiClient(
          baseUrl: 'https://example.supabase.co',
          publicKey: 'public',
          token: () async => 'jwt',
          client: MockClient((_) async => http.Response(body, 200)),
        );
        expect((await client.rpcRecord('publish_request', {}))['version'], 1);
        client.close();
      }
      final client = ApiClient(
        baseUrl: 'https://example.supabase.co',
        publicKey: 'public',
        token: () async => 'jwt',
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      await expectLater(
        client.rpcRecord('publish_request', {}),
        throwsA(isA<ApiFailure>()),
      );
      client.close();
    },
  );
  test('Una operación de otra cuenta no utiliza el nuevo JWT', () async {
    final jwt =
        'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'new-owner'})))}.signature';
    var called = false;
    final client = ApiClient(
      baseUrl: 'https://example.supabase.co',
      publicKey: 'public',
      token: () async => jwt,
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.rpc('publish_request', {}, expectedSubject: 'old-owner'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(called, false);
    client.close();
  });
  ApiClient api(
    Future<http.Response> Function(http.Request) handler, {
    Duration? timeout,
  }) => ApiClient(
    baseUrl: 'https://example.supabase.co',
    publicKey: 'public',
    token: () async => 'jwt',
    client: MockClient(handler),
    timeout: timeout ?? const Duration(seconds: 1),
  );
  test('GET autenticado y JSON real', () async {
    final client = api((r) async {
      expect(r.method, 'GET');
      expect(r.headers['Authorization'], 'Bearer jwt');
      expect(r.url.queryParameters['limit'], '30');
      return http.Response('[{"id":"a"}]', 200);
    });
    expect(
      (await client.select('requests', query: {'limit': 30})).single['id'],
      'a',
    );
    client.close();
  });
  for (final status in [401, 403, 404, 409, 429, 500]) {
    test('HTTP $status se distingue y no se marca éxito', () async {
      final client = api((_) async => http.Response('{}', status));
      await expectLater(
        client.rpc('publish_request', {}),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.status, 'status', status)
              .having(
                (e) => e.retryable,
                'retryable',
                status == 429 || status >= 500,
              ),
        ),
      );
      client.close();
    });
  }
  test('JSON inválido produce fallo recuperable', () async {
    final client = api((_) async => http.Response('<html>error</html>', 200));
    await expectLater(
      client.select('requests'),
      throwsA(isA<ApiFailure>().having((e) => e.retryable, 'retryable', true)),
    );
    client.close();
  });
  test('Timeout conserva error recuperable', () async {
    final client = api(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      client.select('requests'),
      throwsA(isA<ApiFailure>().having((e) => e.retryable, 'retryable', true)),
    );
    client.close();
  });
}

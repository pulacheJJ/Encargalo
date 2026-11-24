import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:encargalo/core/storage/local_database.dart';
import 'package:encargalo/core/network/api_client.dart';
import 'package:encargalo/features/payments/data/commerce_repository.dart';

void main() {
  sqfliteFfiInit();
  test(
    'Pago incierto conserva operación persistente al reabrir repositorio',
    () async {
      final local = LocalDatabase(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: LocalDatabase.create,
          ),
        ),
      );
      final subject = base64Url
          .encode(utf8.encode('{"sub":"owner"}'))
          .replaceAll('=', '');
      final operations = <String>[];
      final client = MockClient((request) async {
        operations.add(jsonDecode(request.body)['p_operation']);
        return http.Response(
          operations.length == 1 ? '{}' : '{"simulated":true}',
          operations.length == 1 ? 503 : 200,
        );
      });
      final api = ApiClient(
        baseUrl: 'https://fixture.invalid',
        publicKey: 'fixture',
        token: () async => 'header.$subject.signature',
        client: client,
      );
      try {
        await expectLater(
          CommerceRepository(
            api,
            local,
            () => 'owner',
          ).pay('order', 100, true, 1),
          throwsA(isA<ApiFailure>()),
        );
        await CommerceRepository(
          api,
          local,
          () => 'owner',
        ).pay('order', 100, true, 1);
        expect(operations.length, 2);
        expect(operations[0], operations[1]);
        expect(
          await local.cached(
            'commerce-operation:owner:simulate_order_payment:order:100:true',
          ),
          isNull,
        );
      } finally {
        api.close();
        await local.db.close();
      }
    },
  );
  test(
    'Asignación transaccional de operación no duplica identificadores pendientes',
    () async {
      final local = LocalDatabase(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: LocalDatabase.create,
          ),
        ),
      );
      try {
        final operations = await Future.wait([
          local.operationFor('intent'),
          local.operationFor('intent'),
        ]);
        expect(operations[0], operations[1]);
      } finally {
        await local.db.close();
      }
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:encargalo/core/domain/models.dart';
import 'package:encargalo/core/storage/local_database.dart';

void main() {
  sqfliteFfiInit();
  late LocalDatabase local;
  setUp(() async {
    local = LocalDatabase(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: LocalDatabase.create,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        ),
      ),
    );
  });
  tearDown(() async => local.db.close());
  RequestDraft draft() => RequestDraft(
    id: uuid.v4(),
    ownerId: 'owner',
    title: 'Bordado UNP',
    detail: 'Bordado para uniformes de algodón',
    categoryId: 'bordado',
    photos: [
      Photo(
        id: uuid.v4(),
        localPath: 'fixture/foto_inexistente.jpg',
        bytes: 300,
      ),
    ],
  );
  test('CRUD y separación entre propietarios', () async {
    final d = draft();
    await local.saveDraft(d);
    expect((await local.drafts('owner')).single.id, d.id);
    expect(await local.drafts('otro'), isEmpty);
    d.title = 'Título editado';
    await local.saveDraft(d);
    expect((await local.draft(d.id, 'owner'))!.title, 'Título editado');
    await local.removeDraft(d.id, 'otro');
    expect(await local.draft(d.id, 'owner'), isNotNull);
    await local.removeDraft(d.id, 'owner');
    expect(await local.drafts('owner'), isEmpty);
  });
  test(
    'Cola: idempotencia local, lease entre dos workers, no confirmar ante fallo',
    () async {
      final d = draft();
      await local.enqueue(d);
      await expectLater(local.enqueue(d), throwsStateError);
      final a = await local.claim('owner');
      expect(a, isNotNull);
      expect(await local.claim('owner'), isNull);
      await local.failed(a!, 'Timeout');
      expect((await local.draft(d.id, 'owner'))!.syncState, 'pending');
      expect((await local.pending('owner')).length, 1);
      await local.retry('owner', a['id']);
      final b = await local.claim('owner');
      expect(b!['id'], a['id']);
      await local.confirmed(b, 1);
      expect(await local.pending('owner'), isEmpty);
      expect((await local.draft(d.id, 'owner'))!.remoteVersion, 1);
    },
  );
  test('Eventos push se deduplican de forma persistente', () async {
    expect(await local.firstEvent('evento'), true);
    expect(await local.firstEvent('evento'), false);
  });
  test(
    'Cotización offline usa snapshot y operación estable, no duplica y conserva borrador al detener',
    () async {
      final id = uuid.v4(), request = uuid.v4(), op = uuid.v4();
      final data = <String, dynamic>{
        'id': id,
        'request_id': request,
        'total_cents': 12300,
      };
      final key = 'quote-draft:owner:$request';
      await local.cache(
        key,
        jsonEncode({'operation': op}),
        const Duration(days: 1),
      );
      await local.enqueueQuote('owner', data, op, 0);
      await local.enqueueQuote('owner', data, op, 0);
      expect((await local.pending('owner')).length, 1);
      data['total_cents'] = 99999;
      await expectLater(
        local.enqueueQuote('owner', data, op, 0),
        throwsStateError,
      );
      final claimed = await local.claim('owner');
      expect(
        jsonDecode(claimed!['payload'] as String)['data']['total_cents'],
        12300,
      );
      await local.confirmed(claimed, 1);
      expect(await local.cached(key), null);
      final op2 = uuid.v4();
      await local.cache(
        key,
        jsonEncode({'operation': op2}),
        const Duration(days: 1),
      );
      await local.enqueueQuote('owner', data, op2, 1);
      await local.abandon('owner', op2);
      expect(await local.pending('owner'), isEmpty);
      expect(await local.cached(key), isNotNull);
    },
  );
  test(
    'Migración SQLite v1 conserva ID, propietario y referencia inválida sin publicarla',
    () async {
      final dir = await Directory.systemTemp.createTemp('encargalo_fixture_');
      final path = '${dir.path}/v1.db';
      final d = draft();
      var db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => LocalDatabase.createV1(db),
        ),
      );
      await db.insert('drafts', {
        'id': d.id,
        'owner': d.ownerId,
        'payload': jsonEncode(d.toLocal()),
        'updated': '2026-11-23',
      });
      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onUpgrade: LocalDatabase.upgrade,
        ),
      );
      final migrated = LocalDatabase(db);
      final after = await migrated.draft(d.id, 'owner');
      expect(after!.id, d.id);
      expect(after.photos.single.localPath, d.photos.single.localPath);
      expect(
        await migrated.referencedPaths(),
        contains('fixture/foto_inexistente.jpg'),
      );
      expect(await migrated.pending('owner'), isEmpty);
      await db.close();
      await File(path).delete();
      await dir.delete();
    },
  );
}

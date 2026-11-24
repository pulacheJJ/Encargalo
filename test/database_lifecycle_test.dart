import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:encargalo/core/storage/local_database.dart';
import 'package:encargalo/core/domain/models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  final connections = <LocalDatabase>[];

  Future<LocalDatabase> openConnection() async {
    final local = await LocalDatabase.open();
    connections.add(local);
    return local;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('encargalo_lifecycle_');
    await databaseFactoryFfi.setDatabasesPath(directory.path);
  });
  tearDown(() async {
    for (final local in connections) {
      if (local.db.isOpen) await local.db.close();
    }
    connections.clear();
    await databaseFactoryFfi.deleteDatabase(
      p.join(directory.path, 'encargalo.db'),
    );
    await directory.delete();
  });

  test('Control: singleton reproduce el cierre compartido observado', () async {
    final path = p.join(directory.path, 'encargalo.db');
    final foreground = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 2, onCreate: LocalDatabase.create),
    );
    final worker = await databaseFactoryFfi.openDatabase(path);
    connections.add(LocalDatabase(foreground));
    connections.add(LocalDatabase(worker));
    expect(identical(foreground, worker), isTrue);
    await worker.close();
    expect(foreground.isOpen, isFalse);
    await expectLater(
      () => foreground.query('drafts'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('Cerrar un worker no cierra SQLite de la pantalla abierta', () async {
    final foreground = await openConnection();
    final worker = await openConnection();
    await foreground.cache('perfil', 'conservado', const Duration(days: 1));

    await worker.db.close();

    expect(foreground.db.isOpen, isTrue);
    expect(await foreground.cached('perfil'), 'conservado');
    await foreground.cache('posterior', 'disponible', const Duration(days: 1));
    expect(await foreground.cached('posterior'), 'disponible');
  });

  test(
    'Cerrar FCM y sincronizacion conserva borrador, cola y deduplicacion',
    () async {
      final foreground = await openConnection();
      final worker = await openConnection();
      final push = await openConnection();
      final draft = RequestDraft(
        id: uuid.v4(),
        ownerId: 'owner',
        title: 'Borrador que debe conservarse',
      );
      await foreground.enqueue(draft);
      final operation = await worker.claim('owner');
      expect(operation, isNotNull);
      expect(await push.claim('owner'), isNull);
      expect(await push.firstEvent('evento-persistente'), isTrue);

      await push.db.close();
      await worker.db.close();

      expect((await foreground.draft(draft.id, 'owner'))!.syncState, 'pending');
      expect(
        (await foreground.pending('owner')).single['id'],
        operation!['id'],
      );
      expect(await foreground.firstEvent('evento-persistente'), isFalse);
      expect(await foreground.drafts('otro'), isEmpty);

      final nextWorker = await openConnection();
      await nextWorker.failed(operation, 'Sin conexion');
      await nextWorker.db.close();
      await foreground.retry('owner', operation['id']);
      expect((await foreground.claim('owner'))!['id'], operation['id']);
    },
  );

  test('Cerrar pantalla no invalida la conexion de un worker activo', () async {
    final foreground = await openConnection();
    final worker = await openConnection();
    await foreground.cache(
      'persistente',
      'sin borrar',
      const Duration(days: 1),
    );
    await foreground.db.close();

    expect(worker.db.isOpen, isTrue);
    expect(await worker.cached('persistente'), 'sin borrar');
    await worker.cache('worker', 'terminado', const Duration(days: 1));
    await worker.db.close();

    final reopened = await openConnection();
    expect(await reopened.cached('persistente'), 'sin borrar');
    expect(await reopened.cached('worker'), 'terminado');
  });
}

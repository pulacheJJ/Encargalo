import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';

class LocalDatabase {
  final Database db;
  LocalDatabase(this.db);
  static Future<LocalDatabase> open() async => LocalDatabase(
    await openDatabase(
      p.join(await getDatabasesPath(), 'encargalo.db'),
      version: 2,
      // Foreground, WorkManager and FCM own their connection lifetimes. Native
      // sqflite singleton handles may be shared across engines; a worker closing
      // one must not invalidate the database still used by an open screen.
      // All connections retain the same file/schema and transactional leases.
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: create,
      onUpgrade: upgrade,
    ),
  );
  static Future<void> createV1(Database db) async {
    await db.execute(
      'CREATE TABLE drafts(id TEXT PRIMARY KEY, owner TEXT, payload TEXT NOT NULL, updated TEXT NOT NULL)',
    );
  }

  static Future<void> create(Database db, int version) async {
    await createV1(db);
    await upgrade(db, 1, 2);
  }

  static Future<void> upgrade(Database db, int old, int target) async {
    if (old < 2) {
      await db.execute(
        'CREATE TABLE attachments(id TEXT PRIMARY KEY,draft_id TEXT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,path TEXT)',
      );
      await db.execute(
        'CREATE TABLE queue(id TEXT PRIMARY KEY, owner TEXT NOT NULL, entity TEXT NOT NULL UNIQUE, action TEXT NOT NULL,payload TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_run INTEGER NOT NULL DEFAULT 0,lease_until INTEGER NOT NULL DEFAULT 0,error TEXT)',
      );
      await db.execute(
        'CREATE TABLE seen_events(id TEXT PRIMARY KEY,created INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE cache(key TEXT PRIMARY KEY,payload TEXT NOT NULL,expires INTEGER NOT NULL)',
      );
      for (final row in await db.query('drafts')) {
        final j = jsonDecode(row['payload'] as String) as Json;
        for (final photo in j['photos'] as List? ?? []) {
          if (photo is Map && photo['id'] != null) {
            await db.insert('attachments', {
              'id': photo['id'],
              'draft_id': row['id'],
              'path': photo['local_path'],
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }
    }
  }

  Future<void> _save(DatabaseExecutor tx, RequestDraft draft) async {
    await tx.insert('drafts', {
      'id': draft.id,
      'owner': draft.ownerId,
      'payload': jsonEncode(draft.toLocal()),
      'updated': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await tx.delete('attachments', where: 'draft_id=?', whereArgs: [draft.id]);
    for (final photo in draft.photos) {
      await tx.insert('attachments', {
        'id': photo.id,
        'draft_id': draft.id,
        'path': photo.localPath,
      });
    }
  }

  Future<void> saveDraft(RequestDraft draft) {
    final snapshot = RequestDraft.fromLocal(draft.toLocal());
    return db.transaction((tx) => _save(tx, snapshot));
  }

  Future<RequestDraft?> draft(String id, String owner) async {
    final rows = await db.query(
      'drafts',
      where: 'id=? AND owner=?',
      whereArgs: [id, owner],
    );
    return rows.isEmpty
        ? null
        : RequestDraft.fromLocal(jsonDecode(rows.first['payload'] as String));
  }

  Future<List<RequestDraft>> drafts(String owner) async =>
      (await db.query(
            'drafts',
            where: 'owner=?',
            whereArgs: [owner],
            orderBy: 'updated DESC',
          ))
          .map(
            (r) => RequestDraft.fromLocal(jsonDecode(r['payload'] as String)),
          )
          .toList();
  Future<void> removeDraft(String id, String owner) async {
    await db.transaction((tx) async {
      final pending = await tx.query(
        'queue',
        where: 'entity=? AND owner=?',
        whereArgs: [id, owner],
      );
      if (pending.isNotEmpty) {
        throw StateError('Primero debe resolverse la publicación pendiente.');
      }
      await tx.delete(
        'drafts',
        where: 'id=? AND owner=?',
        whereArgs: [id, owner],
      );
    });
  }

  Future<void> enqueue(RequestDraft draft, {String action = 'publish'}) async {
    await db.transaction((tx) async {
      final pending = await tx.query(
        'queue',
        where: 'entity=?',
        whereArgs: [draft.id],
      );
      if (pending.isNotEmpty) {
        throw StateError('Ya hay una operación pendiente para esta solicitud.');
      }
      draft.operation = uuid.v4();
      draft.syncState = 'pending';
      await _save(tx, draft);
      await tx.insert('queue', {
        'id': draft.operation,
        'owner': draft.ownerId,
        'entity': draft.id,
        'action': action,
        'payload': jsonEncode(draft.toLocal()),
      });
    });
  }

  Future<void> enqueueQuote(
    String owner,
    Json data,
    String operation,
    int version,
  ) async {
    final payload = jsonEncode({
      'owner_id': owner,
      'data': data,
      'expected_version': version,
    });
    await db.transaction((tx) async {
      final existing = await tx.query(
        'queue',
        where: 'entity=?',
        whereArgs: [data['id']],
      );
      if (existing.isNotEmpty) {
        if (existing.single['id'] == operation &&
            existing.single['payload'] == payload) {
          return;
        }
        throw StateError(
          'Esta cotización tiene un envío pendiente. Revíselo en Sincronización antes de cambiarlo.',
        );
      }
      await tx.insert('queue', {
        'id': operation,
        'owner': owner,
        'entity': data['id'],
        'action': 'quote',
        'payload': payload,
      });
    });
  }

  Future<List<Json>> pending(String owner) => db.query(
    'queue',
    where: 'owner=?',
    whereArgs: [owner],
    orderBy: 'next_run',
  );
  Future<Json?> claim(String owner, {String? operation}) => db.transaction((
    tx,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await tx.query(
      'queue',
      where:
          'owner=? AND next_run<=? AND lease_until<?${operation == null ? '' : ' AND id=?'}',
      whereArgs: [owner, now, now, if (operation != null) operation],
      orderBy: 'next_run',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await tx.update(
      'queue',
      {'lease_until': now + 180000},
      where: 'id=?',
      whereArgs: [rows.first['id']],
    );
    return rows.first;
  });
  Future<void> confirmed(Json operation, int version) async {
    await db.transaction((tx) async {
      final rows = await tx.query(
        'drafts',
        where: 'id=? AND owner=?',
        whereArgs: [operation['entity'], operation['owner']],
      );
      if (rows.isNotEmpty) {
        final d = RequestDraft.fromLocal(
          jsonDecode(rows.first['payload'] as String),
        );
        if (d.operation == operation['id']) {
          d.syncState = operation['action'] == 'delete' ? 'deleted' : 'synced';
          d.remoteVersion = version;
          await _save(tx, d);
        }
      }
      await tx.delete(
        'queue',
        where: 'id=? AND owner=?',
        whereArgs: [operation['id'], operation['owner']],
      );
      if (operation['action'] == 'quote') {
        final payload = jsonDecode(operation['payload'] as String) as Json;
        final key =
            'quote-draft:${operation['owner']}:${payload['data']['request_id']}';
        final cacheRows = await tx.query(
          'cache',
          where: 'key=?',
          whereArgs: [key],
        );
        if (cacheRows.isNotEmpty &&
            jsonDecode(cacheRows.single['payload'] as String)['operation'] ==
                operation['id']) {
          await tx.delete('cache', where: 'key=?', whereArgs: [key]);
        }
      }
    });
  }

  Future<void> failed(
    Json operation,
    String error, {
    bool retryable = true,
  }) async {
    final attempts = (operation['attempts'] as int) + 1;
    final delay = retryable ? (30 * (1 << attempts.clamp(0, 7))) : 86400;
    await db.update(
      'queue',
      {
        'attempts': attempts,
        'error': error,
        'lease_until': 0,
        'next_run': DateTime.now().millisecondsSinceEpoch + delay * 1000,
      },
      where: 'id=?',
      whereArgs: [operation['id']],
    );
  }

  Future<void> retry(String owner, String id) => db.update(
    'queue',
    {'next_run': 0, 'error': null},
    where: 'id=? AND owner=?',
    whereArgs: [id, owner],
  );
  Future<void> abandon(String owner, String id) async {
    await db.transaction((tx) async {
      final rows = await tx.query(
        'queue',
        where: 'id=? AND owner=?',
        whereArgs: [id, owner],
      );
      if (rows.isEmpty) return;
      if ((rows.first['lease_until'] as int) >
          DateTime.now().millisecondsSinceEpoch) {
        throw StateError(
          'Hay una sincronización en curso. Espere a que finalice.',
        );
      }
      if (rows.first['action'] != 'quote') {
        final d = RequestDraft.fromLocal(
          jsonDecode(rows.first['payload'] as String),
        );
        d.syncState = 'draft';
        d.operation = null;
        await _save(tx, d);
      }
      await tx.delete(
        'queue',
        where: 'id=? AND owner=?',
        whereArgs: [id, owner],
      );
    });
  }

  Future<bool> firstEvent(String id) async {
    return db.transaction((tx) async {
      final exists = await tx.query(
        'seen_events',
        where: 'id=?',
        whereArgs: [id],
      );
      if (exists.isNotEmpty) return false;
      await tx.insert('seen_events', {
        'id': id,
        'created': DateTime.now().millisecondsSinceEpoch,
      });
      await tx.delete(
        'seen_events',
        where: 'created<?',
        whereArgs: [
          DateTime.now()
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        ],
      );
      return true;
    });
  }

  Future<String?> cached(String key) async {
    final rows = await db.query(
      'cache',
      where: 'key=? AND expires>?',
      whereArgs: [key, DateTime.now().millisecondsSinceEpoch],
    );
    return rows.isEmpty ? null : rows.first['payload'] as String;
  }

  Future<void> cache(String key, String value, Duration duration) =>
      db.insert('cache', {
        'key': key,
        'payload': value,
        'expires': DateTime.now().add(duration).millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<String> operationFor(String key) => db.transaction((tx) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await tx.query(
      'cache',
      where: 'key=? AND expires>?',
      whereArgs: [key, now],
    );
    if (rows.isNotEmpty) {
      return jsonDecode(rows.single['payload'] as String)['operation']
          as String;
    }
    final operation = uuid.v4();
    await tx.insert('cache', {
      'key': key,
      'payload': jsonEncode({'operation': operation}),
      'expires':
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return operation;
  });
  Future<void> completeOperation(String key, String operation) => db.delete(
    'cache',
    where: 'key=? AND payload=?',
    whereArgs: [
      key,
      jsonEncode({'operation': operation}),
    ],
  );
  Future<Set<String>> referencedPaths() async =>
      (await db.query(
        'attachments',
        columns: ['path'],
      )).map((r) => r['path']).whereType<String>().toSet();
}

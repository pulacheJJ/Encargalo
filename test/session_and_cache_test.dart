import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:encargalo/core/async/single_flight.dart';
import 'package:encargalo/core/network/query_cache.dart';

void main() {
  test(
    'Eventos de la misma sesión comparten una carga; otra cuenta no',
    () async {
      final flight = SingleFlight<String>();
      final first = Completer<String>();
      var calls = 0;
      final a = flight.run('a', () {
        calls++;
        return first.future;
      });
      final repeated = flight.run('a', () {
        calls++;
        return Future.value('duplicado');
      });
      expect(identical(a, repeated), isTrue);
      expect(calls, 1);
      final b = flight.run('b', () async => 'cuenta-b');
      expect(await b, 'cuenta-b');
      first.complete('cuenta-a');
      expect(await a, 'cuenta-a');
      expect(await flight.run('a', () async => 'recarga'), 'recarga');
    },
  );
  test('Carga fallida puede reintentarse sin reutilizar el fallo', () async {
    final flight = SingleFlight<int>();
    await expectLater(
      flight.run('a', () async => throw StateError('sin red')),
      throwsStateError,
    );
    expect(await flight.run('a', () async => 2), 2);
  });
  test('Caché agrupa consultas y respeta expiración e invalidación', () async {
    var now = DateTime(2026);
    final cache = QueryCache(now: () => now);
    var calls = 0;
    Future<int> load() async => ++calls;
    final values = await Future.wait([
      cache.get('u1/feed', load),
      cache.get('u1/feed', load),
    ]);
    expect(values, [1, 1]);
    expect(await cache.get('u2/feed', load), 2);
    now = now.add(const Duration(seconds: 10));
    expect(await cache.get('u1/feed', load), 3);
    cache.invalidate();
    expect(await cache.get('u1/feed', load), 4);
  });
  test(
    'Respuesta anterior a invalidación no rellena caché de otra sesión',
    () async {
      final cache = QueryCache();
      final delayed = Completer<int>();
      final pending = cache.get('feed', () => delayed.future);
      cache.invalidate();
      expect(await cache.get('feed', () async => 2), 2);
      delayed.complete(1);
      expect(await pending, 1);
      expect(await cache.get('feed', () async => 3), 2);
    },
  );
}

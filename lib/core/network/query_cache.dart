/// Short-lived, account-scoped query cache. Concurrent identical queries share
/// one request. Mutations and Realtime invalidate it; failures are never cached.
class QueryCache {
  final DateTime Function() now;
  final _values = <String, ({Object value, DateTime expires})>{};
  final _pending = <String, Future<Object>>{};
  int _generation = 0;
  QueryCache({DateTime Function()? now}) : now = now ?? DateTime.now;

  Future<T> get<T extends Object>(
    String key,
    Future<T> Function() load, {
    Duration ttl = const Duration(seconds: 8),
  }) async {
    final cached = _values[key];
    if (cached != null && now().isBefore(cached.expires)) {
      return cached.value as T;
    }
    final pending = _pending[key];
    if (pending != null) return await pending as T;
    final generation = _generation;
    final future = Future<T>.sync(load);
    _pending[key] = future;
    try {
      final result = await future;
      if (generation == _generation) {
        _values[key] = (value: result, expires: now().add(ttl));
      }
      return result;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  void invalidate() {
    _generation++;
    _values.clear();
    _pending.clear();
  }
}

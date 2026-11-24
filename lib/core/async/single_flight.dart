/// Coalesces concurrent work for one identity without hiding failures or
/// reusing a previous user's result. Completed results are not cached.
class SingleFlight<T> {
  Object? _key;
  Future<T>? _running;

  Future<T> run(Object key, Future<T> Function() action) {
    if (_key == key && _running != null) return _running!;
    _key = key;
    late final Future<T> future;
    future = Future<T>.sync(action).whenComplete(() {
      if (identical(_running, future)) {
        _running = null;
        _key = null;
      }
    });
    _running = future;
    return future;
  }
}

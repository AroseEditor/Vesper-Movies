import 'dart:async';

class _Entry<T> {
  _Entry(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class MemoCache<K, V> {
  MemoCache({this.ttl = const Duration(minutes: 30), this.maxEntries = 256});

  final Duration ttl;
  final int maxEntries;

  final Map<K, _Entry<V>> _entries = {};
  final Map<K, Future<V>> _inFlight = {};

  V? peek(K key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!entry.isFresh) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void put(K key, V value) {
    if (_entries.length >= maxEntries) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
    }
    _entries[key] = _Entry(value, DateTime.now().add(ttl));
  }

  Future<V> resolve(K key, Future<V> Function() load) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = load()
        .then((value) {
          put(key, value);
          return value;
        })
        .whenComplete(() => _inFlight.remove(key));

    _inFlight[key] = future;
    return future;
  }

  void invalidate(K key) {
    _entries.remove(key);
    _inFlight.remove(key);
  }

  void clear() {
    _entries.clear();
    _inFlight.clear();
  }

  int get length => _entries.length;
}

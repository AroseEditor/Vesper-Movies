import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class _Entry<T> {
  _Entry(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class MemoCache<K, V> {
  MemoCache({
    this.ttl = const Duration(minutes: 30),
    this.maxEntries = 256,
    this.name,
    this.encode,
    this.decode,
  }) {
    if (name != null && encode != null && decode != null) {
      _registry.add(this);
      _hydrate();
    }
  }

  static final List<MemoCache<Object?, Object?>> _registry = [];
  static Directory? _dir;
  static bool _diskReady = false;

  static Future<void> openDisk() async {
    if (_diskReady) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}${Platform.pathSeparator}cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
    } on Object {
      _dir = null;
    }
    _diskReady = true;
    for (final cache in _registry) {
      cache._hydrate();
    }
  }

  static Future<void> flushAll() async {
    for (final cache in _registry) {
      cache._writeNow();
    }
  }

  final Duration ttl;
  final int maxEntries;
  final String? name;
  final Object? Function(V value)? encode;
  final V Function(Object? raw)? decode;

  final Map<K, _Entry<V>> _entries = {};
  final Map<K, Future<V>> _inFlight = {};

  bool _loaded = false;
  Timer? _writeTimer;

  File? get _file {
    final dir = _dir;
    if (dir == null || name == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name.json');
  }

  void _hydrate() {
    if (_loaded || !_diskReady) return;
    _loaded = true;

    final file = _file;
    if (file == null || !file.existsSync()) return;

    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return;

      final now = DateTime.now();
      for (final entry in raw.entries) {
        final record = entry.value;
        if (record is! Map) continue;

        final expiry = record['e'];
        if (expiry is! int) continue;

        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry);
        if (!now.isBefore(expiresAt)) continue;

        if (_entries.containsKey(entry.key as K)) continue;
        _entries[entry.key as K] = _Entry(decode!(record['v']), expiresAt);
      }
    } on Object {
      try {
        file.deleteSync();
      } on Object {
        // a corrupt cache file is not worth failing over
      }
    }
  }

  void _schedule() {
    if (_file == null) return;
    _writeTimer?.cancel();
    _writeTimer = Timer(const Duration(seconds: 3), _writeNow);
  }

  void _writeNow() {
    _writeTimer?.cancel();
    _writeTimer = null;

    final file = _file;
    if (file == null) return;

    try {
      final payload = <String, Object?>{};
      for (final entry in _entries.entries) {
        if (!entry.value.isFresh) continue;
        payload['${entry.key}'] = {
          'e': entry.value.expiresAt.millisecondsSinceEpoch,
          'v': encode!(entry.value.value),
        };
      }
      file.writeAsStringSync(jsonEncode(payload), flush: true);
    } on Object {
      // losing a cache write only costs a refetch
    }
  }

  V? peek(K key) {
    _hydrate();
    final entry = _entries[key];
    if (entry == null) return null;
    if (!entry.isFresh) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void put(K key, V value) {
    _hydrate();
    if (_entries.length >= maxEntries) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
    }
    _entries[key] = _Entry(value, DateTime.now().add(ttl));
    _schedule();
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
        .whenComplete(() {
          _inFlight.remove(key);
        });

    _inFlight[key] = future;
    return future;
  }

  void invalidate(K key) {
    _entries.remove(key);
    _inFlight.remove(key);
    _schedule();
  }

  void clear() {
    _entries.clear();
    _inFlight.clear();
    _schedule();
  }

  int get length => _entries.length;
}

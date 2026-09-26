import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_kind.dart';

const _key = 'pref.source_health';
const _limit = 4;

class SourceHealthNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    unawaited(_load());
    return const {'moviesmod': 2, 'archive': 1};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      state = {
        ...state,
        for (final entry in decoded.entries)
          if (entry.value is int) '${entry.key}': entry.value as int,
      };
    } on Object {
      return;
    }
  }

  void record(ProviderKind kind, {required bool ok}) {
    final next = {...state};
    final value = (next[kind.id] ?? 0) + (ok ? 1 : -1);
    next[kind.id] = value.clamp(-_limit, _limit);
    state = next;
    unawaited(_save(next));
  }

  Future<void> _save(Map<String, int> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(value));
    } on Object {
      return;
    }
  }
}

final sourceHealthProvider = NotifierProvider<SourceHealthNotifier, Map<String, int>>(
  SourceHealthNotifier.new,
);

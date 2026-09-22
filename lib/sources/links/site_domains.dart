import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lists = [
  'https://raw.githubusercontent.com/SaurabhKaperwan/Utils/refs/heads/main/urls.json',
  'https://raw.githubusercontent.com/phisher98/TVVVV/refs/heads/main/domains.json',
];

const _prefsKey = 'sources.domains';

const Map<String, String> _defaults = {
  'hdhub4u': 'https://new6.hdhub4u.cl',
  'vegamovies': 'https://vegamovies.gallery',
  'moviesdrive': 'https://new4.moviesdrive.christmas',
  'bollyflix': 'https://bollyflix.af',
  'movies4u': 'https://new6.movies4u.clinic',
  'hdmovie2': 'https://hdmovie2a.live',
  'skymovies': 'https://skymovieshd.tube',
  'filmycab': 'https://filmycab.us',
  'uhdmovies': 'https://uhdmovies.my',
  'topmovies': 'https://moviesleech.club',
  '4khdhub': 'https://4khdhub.one',
  'hubcloud': 'https://hubcloud.ist',
  'vcloud': 'https://vcloud.fit',
  'gdflix': 'https://new4.gdflix.io',
};

abstract final class SiteDomains {
  static final Map<String, String> _current = {..._defaults};
  static bool _loaded = false;

  static String of(String key) => _current[key] ?? _defaults[key] ?? '';

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) _merge(jsonDecode(saved));
    } on Object {
      return;
    } finally {
      unawaited(refresh());
    }
  }

  static Future<void> refresh() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.plain,
      ),
    );
    final merged = <String, String>{};
    for (final url in _lists.reversed) {
      try {
        final response = await dio.get<String>(url);
        final decoded = jsonDecode(response.data ?? '');
        if (decoded is! Map) continue;
        for (final entry in decoded.entries) {
          final value = '${entry.value}';
          if (!value.startsWith('https://') || value.contains('suspended')) continue;
          merged['${entry.key}'.toLowerCase()] = value.replaceAll(RegExp(r'/+$'), '');
        }
      } on Object {
        continue;
      }
    }
    if (merged.isEmpty) return;
    _merge(merged);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(merged));
    } on Object {
      return;
    }
  }

  static void _merge(Object? decoded) {
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      final value = '${entry.value}';
      if (value.startsWith('https://')) _current['${entry.key}'.toLowerCase()] = value;
    }
  }
}

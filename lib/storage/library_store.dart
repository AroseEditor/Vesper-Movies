import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/log.dart';
import '../models/media.dart';
import '../models/provider_kind.dart';

class WatchEntry {
  const WatchEntry({
    required this.id,
    required this.title,
    required this.mediaType,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.season = 0,
    this.episode = 0,
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAt = 0,
    this.completed = false,
  });

  final String id;
  final String title;
  final MediaType mediaType;
  final String? year;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final int season;
  final int episode;
  final int positionMs;
  final int durationMs;
  final int updatedAt;
  final bool completed;

  static const completionRatio = 0.92;

  double get progress {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  bool get isInProgress =>
      !completed && durationMs > 0 && progress > 0.01 && progress < completionRatio;

  Duration get resumeAt => Duration(milliseconds: positionMs);

  CatalogItem toCatalogItem() {
    return CatalogItem(
      id: MediaId(ProviderKind.addons, id),
      title: title,
      mediaType: mediaType,
      year: year,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      logoUrl: logoUrl,
    );
  }

  WatchEntry copyWith({int? positionMs, int? durationMs, int? updatedAt, bool? completed}) {
    return WatchEntry(
      id: id,
      title: title,
      mediaType: mediaType,
      year: year,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      logoUrl: logoUrl,
      season: season,
      episode: episode,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'mediaType': mediaType.name,
    'year': year,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'logoUrl': logoUrl,
    'season': season,
    'episode': episode,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt,
    'completed': completed,
  };

  static WatchEntry? fromJson(Object? source) {
    if (source is! Map) return null;
    final id = source['id'];
    final title = source['title'];
    if (id is! String || id.isEmpty || title is! String) return null;

    return WatchEntry(
      id: id,
      title: title,
      mediaType: source['mediaType'] == 'series' ? MediaType.series : MediaType.movie,
      year: source['year'] as String?,
      posterUrl: source['posterUrl'] as String?,
      backdropUrl: source['backdropUrl'] as String?,
      logoUrl: source['logoUrl'] as String?,
      season: _int(source['season']),
      episode: _int(source['episode']),
      positionMs: _int(source['positionMs']),
      durationMs: _int(source['durationMs']),
      updatedAt: _int(source['updatedAt']),
      completed: source['completed'] == true,
    );
  }

  static int _int(Object? value) => value is int ? value : (value is num ? value.toInt() : 0);

  String get key => season > 0 ? '$id:$season:$episode' : id;
}

class LibraryData {
  const LibraryData({this.history = const [], this.favourites = const []});

  final List<WatchEntry> history;
  final List<CatalogItem> favourites;

  List<WatchEntry> get continueWatching {
    final items = history.where((e) => e.isInProgress).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  bool isFavourite(String id) => favourites.any((item) => item.id.value == id);

  WatchEntry? entryFor(String id, {int season = 0, int episode = 0}) {
    final key = season > 0 ? '$id:$season:$episode' : id;
    for (final entry in history) {
      if (entry.key == key) return entry;
    }
    return null;
  }
}

class LibraryStore {
  LibraryStore({this.directory});

  final Directory? directory;
  File? _file;

  static const maxHistory = 120;

  Future<File> _resolveFile() async {
    final existing = _file;
    if (existing != null) return existing;

    final dir = directory ?? await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _file = File(p.join(dir.path, 'library.json'));
  }

  Future<LibraryData> load() async {
    try {
      final file = await _resolveFile();
      if (!file.existsSync()) return const LibraryData();

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const LibraryData();

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const LibraryData();

      final history = <WatchEntry>[];
      final rawHistory = decoded['history'];
      if (rawHistory is List) {
        for (final entry in rawHistory) {
          final parsed = WatchEntry.fromJson(entry);
          if (parsed != null) history.add(parsed);
        }
      }

      final favourites = <CatalogItem>[];
      final rawFavourites = decoded['favourites'];
      if (rawFavourites is List) {
        for (final entry in rawFavourites) {
          final parsed = catalogFromJson(entry);
          if (parsed != null) favourites.add(parsed);
        }
      }

      return LibraryData(history: history, favourites: favourites);
    } on Object catch (error) {
      log.warn('library load failed: ${describeCause(error)}');
      return const LibraryData();
    }
  }

  Future<void> save(LibraryData data) async {
    try {
      final file = await _resolveFile();
      final payload = jsonEncode({
        'history': data.history.take(maxHistory).map((e) => e.toJson()).toList(),
        'favourites': data.favourites.map(catalogToJson).toList(),
      });

      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } on Object catch (error) {
      log.warn('library save failed: ${describeCause(error)}');
    }
  }
}

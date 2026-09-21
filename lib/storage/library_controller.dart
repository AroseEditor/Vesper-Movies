import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media.dart';
import 'library_store.dart';

final libraryStoreProvider = Provider<LibraryStore>((ref) => LibraryStore());

class LibraryNotifier extends AsyncNotifier<LibraryData> {
  Timer? _debounce;

  @override
  Future<LibraryData> build() {
    ref.onDispose(() => _debounce?.cancel());
    return ref.read(libraryStoreProvider).load();
  }

  LibraryData get _current => state.value ?? const LibraryData();

  void _apply(LibraryData next, {bool immediate = false}) {
    state = AsyncValue.data(next);
    _debounce?.cancel();

    if (immediate) {
      unawaited(ref.read(libraryStoreProvider).save(next));
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(ref.read(libraryStoreProvider).save(next));
    });
  }

  Future<void> toggleFavourite(CatalogItem item) async {
    final data = _current;
    final exists = data.isFavourite(item.id.value);

    final favourites = exists
        ? data.favourites.where((e) => e.id.value != item.id.value).toList()
        : [item, ...data.favourites];

    _apply(LibraryData(history: data.history, favourites: favourites), immediate: true);
  }

  Future<void> recordProgress({
    required CatalogItem item,
    required Duration position,
    required Duration duration,
    int season = 0,
    int episode = 0,
    bool completed = false,
  }) async {
    if (duration.inMilliseconds <= 0) return;

    final data = _current;
    final entry = WatchEntry(
      id: item.id.value,
      title: item.title,
      mediaType: item.mediaType,
      year: item.year,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      logoUrl: item.logoUrl,
      season: season,
      episode: episode,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      completed:
          completed ||
          position.inMilliseconds >= duration.inMilliseconds * WatchEntry.completionRatio,
    );

    final history = [entry, ...data.history.where((e) => e.key != entry.key)];
    _apply(LibraryData(history: history, favourites: data.favourites));
  }

  Future<void> setWatched(
    CatalogItem item, {
    required bool watched,
    int season = 0,
    int episode = 0,
  }) async {
    final data = _current;
    final existing = data.entryFor(item.id.value, season: season, episode: episode);

    if (!watched) {
      if (existing == null) return;
      final history = data.history.where((e) => e.key != existing.key).toList();
      _apply(LibraryData(history: history, favourites: data.favourites), immediate: true);
      return;
    }

    final duration = existing != null && existing.durationMs > 0 ? existing.durationMs : 1;
    final entry = WatchEntry(
      id: item.id.value,
      title: item.title,
      mediaType: item.mediaType,
      year: item.year,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      logoUrl: item.logoUrl,
      season: season,
      episode: episode,
      positionMs: duration,
      durationMs: duration,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      completed: true,
    );
    final history = [entry, ...data.history.where((e) => e.key != entry.key)];
    _apply(LibraryData(history: history, favourites: data.favourites), immediate: true);
  }

  Future<void> restore(LibraryData incoming) async {
    final data = _current;

    final byKey = <String, WatchEntry>{for (final entry in data.history) entry.key: entry};
    for (final entry in incoming.history) {
      final existing = byKey[entry.key];
      if (existing == null || entry.updatedAt > existing.updatedAt) byKey[entry.key] = entry;
    }
    final history = byKey.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final favouriteIds = data.favourites.map((e) => e.id.value).toSet();
    final favourites = [
      ...data.favourites,
      for (final item in incoming.favourites)
        if (favouriteIds.add(item.id.value)) item,
    ];

    _apply(LibraryData(history: history, favourites: favourites), immediate: true);
  }

  Future<void> forget(WatchEntry entry) async {
    final data = _current;
    final history = data.history.where((e) => e.key != entry.key).toList();
    _apply(LibraryData(history: history, favourites: data.favourites), immediate: true);
  }

  Future<void> clearHistory() async {
    final data = _current;
    _apply(LibraryData(favourites: data.favourites), immediate: true);
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, LibraryData>(LibraryNotifier.new);

final continueWatchingProvider = Provider<List<WatchEntry>>((ref) {
  return ref.watch(libraryProvider).value?.continueWatching ?? const [];
});

final favouritesProvider = Provider<List<CatalogItem>>((ref) {
  return ref.watch(libraryProvider).value?.favourites ?? const [];
});

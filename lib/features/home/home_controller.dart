import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../metadata/metadata_service.dart';
import '../../metadata/metadata_source.dart';
import '../../models/media.dart';

final metadataServiceProvider = Provider<MetadataService>((ref) => MetadataService());

const _shelfTimeout = Duration(seconds: 25);
const _spotlightTimeout = Duration(seconds: 15);

class HomeShelf {
  const HomeShelf({required this.title, required this.items});

  final String title;
  final List<CatalogItem> items;
}

class HomeFeed {
  const HomeFeed({
    this.spotlight,
    this.shelves = const [],
    this.spotlightOverview,
    this.spotlightPending = false,
  });

  final CatalogItem? spotlight;
  final String? spotlightOverview;
  final List<HomeShelf> shelves;
  final bool spotlightPending;

  bool get isEmpty => shelves.isEmpty;

  HomeFeed copyWith({CatalogItem? spotlight, String? spotlightOverview, bool? spotlightPending}) {
    return HomeFeed(
      spotlight: spotlight ?? this.spotlight,
      spotlightOverview: spotlightOverview ?? this.spotlightOverview,
      shelves: shelves,
      spotlightPending: spotlightPending ?? this.spotlightPending,
    );
  }

  static const empty = HomeFeed();
}

class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  CancelToken? _cancel;

  @override
  Future<HomeFeed> build() {
    ref.keepAlive();
    ref.onDispose(() => _cancel?.cancel());
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<HomeFeed> _load() async {
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;

    final metadata = ref.read(metadataServiceProvider);

    final results = await Future.wait([
      for (final shelf in CatalogShelf.values)
        metadata
            .shelf(shelf, cancel: cancel)
            .timeout(_shelfTimeout, onTimeout: () => const <CatalogItem>[])
            .catchError((_) => const <CatalogItem>[]),
    ]);

    final shelves = <HomeShelf>[];
    for (var i = 0; i < CatalogShelf.values.length; i++) {
      if (results[i].isEmpty) continue;
      shelves.add(HomeShelf(title: CatalogShelf.values[i].title, items: results[i]));
    }

    if (shelves.isEmpty) return HomeFeed.empty;

    final spotlight = _pickSpotlight(shelves);
    final feed = HomeFeed(
      spotlight: spotlight,
      shelves: shelves,
      spotlightPending: spotlight != null,
    );

    if (spotlight != null) {
      unawaited(_fillSpotlight(metadata, spotlight, cancel));
    }
    return feed;
  }

  Future<void> _fillSpotlight(
    MetadataService metadata,
    CatalogItem spotlight,
    CancelToken cancel,
  ) async {
    try {
      final enriched = await metadata
          .enrich(spotlight, cancel: cancel)
          .timeout(_spotlightTimeout, onTimeout: () => spotlight);

      final described = await metadata
          .describe(
            MediaDetails(
              id: enriched.id,
              title: enriched.title,
              mediaType: enriched.mediaType,
              year: enriched.year,
              posterUrl: enriched.posterUrl,
              backdropUrl: enriched.backdropUrl,
              logoUrl: enriched.logoUrl,
            ),
            cancel: cancel,
          )
          .timeout(_spotlightTimeout, onTimeout: () => MediaDetails.of(enriched));

      final current = state.value;
      if (current == null || cancel.isCancelled) return;

      state = AsyncValue.data(
        current.copyWith(
          spotlight: enriched.copyWith(
            backdropUrl: described.backdropUrl,
            logoUrl: described.logoUrl,
          ),
          spotlightOverview: described.description,
          spotlightPending: false,
        ),
      );
    } on Object {
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(spotlightPending: false));
      }
    }
  }

  CatalogItem? _pickSpotlight(List<HomeShelf> shelves) {
    for (final shelf in shelves) {
      for (final item in shelf.items) {
        if (item.posterUrl != null) return item;
      }
    }
    return shelves.first.items.isEmpty ? null : shelves.first.items.first;
  }
}

final homeFeedProvider = AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

class IndianRow {
  const IndianRow(this.title, this.type, this.params);

  final String title;
  final String type;
  final Map<String, dynamic> params;
}

String _today() => DateTime.now().toIso8601String().substring(0, 10);

List<IndianRow> indianRows() {
  final today = _today();
  Map<String, dynamic> movies(String language) => {
    'with_original_language': language,
    'sort_by': 'primary_release_date.desc',
    'primary_release_date.lte': today,
    'vote_count.gte': '2',
    'include_adult': 'false',
  };
  return [
    IndianRow('Latest Bollywood', 'movie', movies('hi')),
    IndianRow('Latest Indian Shows', 'tv', {
      'with_origin_country': 'IN',
      'sort_by': 'first_air_date.desc',
      'first_air_date.lte': today,
      'vote_count.gte': '1',
    }),
    IndianRow('Latest Tamil', 'movie', movies('ta')),
    IndianRow('Latest Telugu', 'movie', movies('te')),
    IndianRow('Latest Malayalam', 'movie', movies('ml')),
    const IndianRow('Popular Indian Shows', 'tv', {
      'with_origin_country': 'IN',
      'sort_by': 'popularity.desc',
    }),
  ];
}

final indianRowProvider = FutureProvider.family<List<CatalogItem>, int>((ref, index) async {
  final rows = indianRows();
  if (index < 0 || index >= rows.length) return const [];
  final row = rows[index];
  return ref.read(metadataServiceProvider).discover(row.type, row.params);
});

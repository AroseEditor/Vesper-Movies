import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../metadata/metadata_service.dart';
import '../../metadata/metadata_source.dart';
import '../../models/media.dart';

final metadataServiceProvider = Provider<MetadataService>((ref) => MetadataService());

class HomeShelf {
  const HomeShelf({required this.title, required this.items});

  final String title;
  final List<CatalogItem> items;
}

class HomeFeed {
  const HomeFeed({this.spotlight, this.shelves = const [], this.spotlightOverview});

  final CatalogItem? spotlight;
  final String? spotlightOverview;
  final List<HomeShelf> shelves;

  bool get isEmpty => shelves.isEmpty;

  static const empty = HomeFeed();
}

class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  @override
  Future<HomeFeed> build() => _load();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<HomeFeed> _load() async {
    final cancel = CancelToken();
    ref.onDispose(cancel.cancel);

    final metadata = ref.read(metadataServiceProvider);

    final results = await Future.wait([
      for (final shelf in CatalogShelf.values) metadata.shelf(shelf, cancel: cancel),
    ]);

    final shelves = <HomeShelf>[];
    for (var i = 0; i < CatalogShelf.values.length; i++) {
      final items = results[i];
      if (items.isEmpty) continue;
      shelves.add(HomeShelf(title: CatalogShelf.values[i].title, items: items));
    }

    if (shelves.isEmpty) return HomeFeed.empty;

    final spotlight = _pickSpotlight(shelves);
    final enriched = spotlight == null ? null : await metadata.enrich(spotlight, cancel: cancel);

    final described = enriched == null
        ? null
        : await metadata.describe(
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
          );

    return HomeFeed(
      spotlight: enriched?.copyWith(
        backdropUrl: described?.backdropUrl,
        logoUrl: described?.logoUrl,
      ),
      spotlightOverview: described?.description,
      shelves: shelves,
    );
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/media.dart';
import '../../models/provider_kind.dart';

class HomeShelf {
  const HomeShelf({required this.title, required this.items});

  final String title;
  final List<CatalogItem> items;
}

class HomeFeed {
  const HomeFeed({required this.spotlight, required this.shelves, this.spotlightOverview});

  final CatalogItem? spotlight;
  final String? spotlightOverview;
  final List<HomeShelf> shelves;

  static const empty = HomeFeed(spotlight: null, shelves: []);
}

CatalogItem _item(
  String id,
  String title,
  String year,
  MediaType type, {
  double? rating,
  int? seasons,
}) {
  return CatalogItem(
    id: MediaId(ProviderKind.moviebox, id),
    title: title,
    mediaType: type,
    year: year,
    rating: rating,
    seasonCount: seasons,
  );
}

const _trending = <CatalogItem>[];

class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  @override
  Future<HomeFeed> build() async {
    await Future<void>.delayed(const Duration(milliseconds: 420));
    return _mockFeed();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      return _mockFeed();
    });
  }

  HomeFeed _mockFeed() {
    final trending = [
      _item('1', 'The Northern Reach', '2025', MediaType.series, rating: 8.4, seasons: 2),
      _item('2', 'Harbour Lights', '2024', MediaType.movie, rating: 7.1),
      _item('3', 'Salt and Iron', '2025', MediaType.movie, rating: 7.8),
      _item('4', 'Quiet Frequency', '2023', MediaType.series, rating: 8.9, seasons: 4),
      _item('5', 'The Long Descent', '2025', MediaType.movie, rating: 6.9),
      _item('6', 'Paper Cities', '2024', MediaType.series, rating: 8.1, seasons: 1),
      _item('7', 'Winter Signal', '2022', MediaType.movie, rating: 7.4),
      _item('8', 'Ninth Hour', '2025', MediaType.series, rating: 8.6, seasons: 3),
    ];

    final newReleases = [
      _item('9', 'Glass Harbour', '2026', MediaType.movie, rating: 7.6),
      _item('10', 'Ember Road', '2026', MediaType.series, rating: 8.2, seasons: 1),
      _item('11', 'After the Flood', '2026', MediaType.movie, rating: 7.0),
      _item('12', 'Static Bloom', '2026', MediaType.movie, rating: 6.5),
      _item('13', 'The Lantern Field', '2026', MediaType.series, rating: 8.8, seasons: 2),
      _item('14', 'Low Tide', '2026', MediaType.movie, rating: 7.3),
    ];

    final topRated = [
      _item('15', 'Meridian', '2019', MediaType.series, rating: 9.1, seasons: 5),
      _item('16', 'The Cartographer', '2021', MediaType.movie, rating: 8.7),
      _item('17', 'Hollow Season', '2020', MediaType.series, rating: 8.9, seasons: 3),
      _item('18', 'Bright Vessel', '2018', MediaType.movie, rating: 8.5),
      _item('19', 'Every Quiet Thing', '2022', MediaType.movie, rating: 8.4),
      _item('20', 'The Understudy', '2017', MediaType.series, rating: 8.3, seasons: 2),
    ];

    return HomeFeed(
      spotlight: trending.first,
      spotlightOverview:
          'A coastal survey crew loses contact with the mainland, and the only signal still '
          'reaching them is one they sent themselves four years ago.',
      shelves: [
        HomeShelf(title: 'Trending Now', items: trending),
        HomeShelf(title: 'New Releases', items: newReleases),
        HomeShelf(title: 'Top Rated', items: topRated),
        HomeShelf(title: 'Because You Watched Meridian', items: [...topRated.reversed]),
      ],
    );
  }
}

final homeFeedProvider = AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

final continueWatchingProvider = Provider<List<CatalogItem>>((ref) => _trending);

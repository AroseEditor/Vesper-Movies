@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/features/details/details_controller.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';

void main() {
  test('a non imdb series still loads every episode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const item = CatalogItem(
      id: MediaId(ProviderKind.moviebox, '8837466153926542360'),
      title: 'Sherlock',
      mediaType: MediaType.series,
      year: '2010',
    );

    final started = DateTime.now();
    final sub = container.listen(titleDetailsProvider(item), (_, _) {});
    addTearDown(sub.close);
    final data = await container.read(titleDetailsProvider(item).future);
    final ms = DateTime.now().difference(started).inMilliseconds;

    debugPrint('PROBE ${data.item.id.value} in ${ms}ms');
    for (final season in data.details.seasons) {
      debugPrint('PROBE   season ${season.number}: ${season.episodes.length} episodes');
    }
    expect(data.item.id.value, startsWith('tt'));
    expect(data.details.seasons, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/features/home/home_controller.dart';

void main() {
  test('home feed resolves without hanging', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final started = DateTime.now();
    final feed = await container
        .read(homeFeedProvider.future)
        .timeout(const Duration(seconds: 60));
    final ms = DateTime.now().difference(started).inMilliseconds;

    debugPrint('PROBE feed in ${ms}ms, shelves=${feed.shelves.length}');
    for (final shelf in feed.shelves) {
      debugPrint('PROBE   ${shelf.title}: ${shelf.items.length}');
    }
    debugPrint('PROBE spotlight=${feed.spotlight?.title}');

    expect(feed.shelves, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 120)));
}

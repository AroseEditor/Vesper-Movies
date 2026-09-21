@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/metadata/cinemeta.dart';

void main() {
  test('search returns real titles with imdb ids, best match first', () async {
    for (final query in ['sherlock', 'interstellar', 'money heist']) {
      final items = await CinemetaSource().search(query);
      debugPrint('PROBE $query -> ${items.length}');
      for (final item in items.take(3)) {
        debugPrint('PROBE   ${item.id.value} ${item.title} ${item.year} ${item.mediaType.name}');
      }
      expect(items.first.id.value, startsWith('tt'));
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}

@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/moviebox/moviebox_source.dart';

void main() {
  test('moviebox returns playable streams', () async {
    final source = MovieBoxSource();
    final started = DateTime.now();

    void mark(String label) {
      debugPrint('PROBE [${DateTime.now().difference(started).inMilliseconds} ms] $label');
    }

    final results = await source.search('Mayday');
    mark('search: ${results.length} results');
    expect(results, isNotEmpty);

    final first = results.first;
    final releases = await source.releases(first.id.value);
    mark('releases: ${releases.length}');
    expect(releases, isNotEmpty);

    for (final release in releases.take(4)) {
      final url = release.directUrl ?? '';
      mark('  ${release.quality} ${release.sizeLabel} -> ${Uri.tryParse(url)?.host}');
      mark('     path ${Uri.tryParse(url)?.path}');
      mark('     headers ${release.mirrors.first.headers.keys.toList()}');
    }

    final playback = await source.resolve(releases.first);
    mark('playback url host ${Uri.tryParse(playback.url)?.host}');
    mark('playback isDash ${playback.isDash}');
    expect(playback.headers.containsKey('Cookie'), isTrue);
    expect(playback.headers.containsKey('Referer'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 120)));
}

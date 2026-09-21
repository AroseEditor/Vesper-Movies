@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/moviebox/moviebox_source.dart';

void main() {
  test('moviebox returns playable streams and subtitles', () async {
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
      mark('  ${release.quality} ${release.codec} ${release.sizeLabel}');
      mark('     host ${Uri.tryParse(url)?.host} resourceId ${release.resourceId}');
    }

    final subtitles = await source.subtitles(first.id.value, resourceId: releases.first.resourceId);
    mark('subtitles: ${subtitles.length}');
    for (final option in subtitles.take(8)) {
      mark('  sub ${option.name} -> ${Uri.tryParse(option.url)?.host}');
    }

    final playback = await source.resolve(releases.first);
    mark('playback isDash ${playback.isDash} headers ${playback.headers.keys.toList()}');
  }, timeout: const Timeout(Duration(seconds: 120)));
}

@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/models/provider_kind.dart';
import 'package:vesper_movies/sources/bdix/circleftp_source.dart';
import 'package:vesper_movies/sources/bdix/dhakaflix_source.dart';
import 'package:vesper_movies/sources/content_source.dart';
import 'package:vesper_movies/sources/dramachi/dramachi_source.dart';
import 'package:vesper_movies/sources/fourkhdhub/fourkhdhub_source.dart';
import 'package:vesper_movies/sources/moviebox/moviebox_source.dart';

void main() {
  test('every registered source answers or fails cleanly', () async {
    final sources = <ProviderKind, ContentSource>{
      ProviderKind.moviebox: MovieBoxSource(),
      ProviderKind.fourkhdhub: FourKHdHubSource(),
      ProviderKind.dramachi: DramachiSource(),
      ProviderKind.circleftp: CircleFtpSource(),
      ProviderKind.dhakaflix: DhakaFlixSource(),
    };

    for (final entry in sources.entries) {
      final started = DateTime.now();
      try {
        final results = await entry.value.search('interstellar');
        final ms = DateTime.now().difference(started).inMilliseconds;
        debugPrint('PROBE ${entry.key.label}: ${results.length} results in ${ms}ms');

        for (final item in results.take(2)) {
          debugPrint('PROBE   ${item.title} (${item.year}) ${item.mediaType.name}');
        }

        if (results.isNotEmpty) {
          try {
            final releases = await entry.value.releases(results.first.id.value);
            debugPrint('PROBE   releases: ${releases.length}');
            for (final release in releases.take(2)) {
              final host = Uri.tryParse(release.directUrl ?? '')?.host;
              debugPrint('PROBE     ${release.quality} ${release.sizeLabel} -> $host');
            }
          } on Object catch (error) {
            debugPrint('PROBE   releases failed: $error');
          }
        }
      } on Object catch (error) {
        final ms = DateTime.now().difference(started).inMilliseconds;
        debugPrint('PROBE ${entry.key.label}: FAILED in ${ms}ms with $error');
      }
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}

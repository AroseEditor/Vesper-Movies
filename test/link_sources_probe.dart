@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/links/link_source.dart';
import 'package:vesper_movies/sources/links/sites/all_sites.dart';
import 'package:vesper_movies/sources/links/web.dart';

const _queries = [
  LinkQuery(title: 'War 2', imdbId: 'tt27425164', year: '2025'),
  LinkQuery(title: 'Panchayat', imdbId: 'tt12004706', year: '2020', season: 1, episode: 2),
];

void main() {
  test('each link source finds and resolves releases', () async {
    final only = const String.fromEnvironment('SITE');
    final web = Web();
    for (final source in buildLinkSources(web).values) {
      if (only.isNotEmpty && source.kind.id != only) continue;
      for (final query in _queries) {
        final label = query.isEpisode
            ? '${query.title} S${query.season}E${query.episode}'
            : query.title;
        final started = DateTime.now();
        try {
          final releases = await source.find(query).timeout(const Duration(seconds: 60));
          final ms = DateTime.now().difference(started).inMilliseconds;
          debugPrint('PROBE ${source.kind.label} [$label]: ${releases.length} releases in ${ms}ms');
          for (final release in releases.take(3)) {
            debugPrint(
              'PROBE   ${release.filename} | ${release.quality} ${release.language ?? ''} '
              '${release.rip ?? ''} ${release.sizeLabel} -> ${release.mirrors.first.label}',
            );
          }
          if (releases.isNotEmpty) {
            final resolved = await source
                .resolve(releases.first)
                .timeout(const Duration(seconds: 60));
            debugPrint('PROBE   resolved -> ${originOf(resolved.url)} (${resolved.sourceLabel})');
          }
        } on Object catch (error) {
          debugPrint('PROBE ${source.kind.label} [$label]: FAILED $error');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

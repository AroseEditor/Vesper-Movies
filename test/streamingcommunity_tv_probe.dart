@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/links/link_source.dart';
import 'package:vesper_movies/sources/links/sites/streamingcommunity_source.dart';
import 'package:vesper_movies/sources/links/web.dart';

void main() {
  test('streamingcommunity resolves a tv episode', () async {
    final source = StreamingCommunitySource(Web());
    const query = LinkQuery(title: 'Lupin', year: '2021', season: 1, episode: 1);
    final releases = await source.find(query).timeout(const Duration(seconds: 30));
    expect(releases, isNotEmpty);
    final resolved = await source.resolve(releases.first).timeout(const Duration(seconds: 30));
    expect(resolved.url, contains('vixcloud.cc'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';
import 'package:vesper_movies/sources/fourkhdhub/fourkhdhub_source.dart';

const _searchHtml = '''
<html><body>
  <a class="movie-card" href="/movie/dune-part-two">
    <img src="https://img.example/dune.jpg">
    <div class="movie-card-title">Dune Part Two</div>
    <span class="metadata-item">2024</span>
    <span class="metadata-item">Movie</span>
  </a>
  <a class="movie-card" href="https://4khdhub.one/series/severance">
    <div class="movie-card-title">Severance</div>
    <span class="metadata-item">2022</span>
    <span class="metadata-item">Season 2</span>
  </a>
  <a class="movie-card" href="/broken"><span class="metadata-item">2020</span></a>
</body></html>
''';

const _moviePageHtml = '''
<html><body>
  <h1>Dune Part Two</h1>
  <span class="metadata-item">2024</span>
  <div class="description">A long awaited sequel.</div>
  <div class="download-item">
    <div class="file-title">Dune.Part.Two.2024.1080p.x265.mkv</div>
    <span class="badge-size">3.4 GB</span>
    <a href="https://pixeldrain.dev/api/file/abc?download">Download</a>
    <a href="https://mirror.example/dune.zip">Zip</a>
    <a href="http://insecure.example/dune.mkv">Insecure</a>
  </div>
</body></html>
''';

const _seriesPageHtml = '''
<html><body>
  <h1>Severance</h1>
  <div id="episodes">
    <div class="episode-download-item">
      <div class="file-title">Severance.S01E01.1080p.mkv</div>
      <span class="badge-size">1.2 GB</span>
      <a href="https://cdn.example/s01e01.mkv">Get</a>
    </div>
    <div class="episode-download-item">
      <div class="file-title">Severance.S01E02.1080p.mkv</div>
      <span class="badge-size">1.1 GB</span>
      <a href="https://cdn.example/s01e02.mkv">Get</a>
    </div>
    <div class="episode-download-item">
      <div class="file-title">Severance.S02E01.2160p.mkv</div>
      <a href="https://cdn.example/s02e01.mkv">Get</a>
    </div>
  </div>
</body></html>
''';

void main() {
  group('search parsing', () {
    test('reads cards, titles, years and type', () {
      final items = parseSearch(html.parse(_searchHtml), ProviderKind.fourkhdhub);

      expect(items, hasLength(2));
      expect(items.first.title, 'Dune Part Two');
      expect(items.first.id.value, '/movie/dune-part-two');
      expect(items.first.year, '2024');
      expect(items.first.mediaType, MediaType.movie);
      expect(items.first.posterUrl, 'https://img.example/dune.jpg');
    });

    test('detects a series from its metadata and normalises absolute links', () {
      final items = parseSearch(html.parse(_searchHtml), ProviderKind.fourkhdhub);

      expect(items.last.mediaType, MediaType.series);
      expect(items.last.id.value, '/series/severance');
    });

    test('drops a card with no title', () {
      final items = parseSearch(html.parse(_searchHtml), ProviderKind.fourkhdhub);
      expect(items.any((e) => e.id.value == '/broken'), isFalse);
    });
  });

  group('details parsing', () {
    test('reads a film', () {
      final details = parseDetails(
        html.parse(_moviePageHtml),
        '/movie/dune-part-two',
        ProviderKind.fourkhdhub,
      );

      expect(details.title, 'Dune Part Two');
      expect(details.year, '2024');
      expect(details.description, 'A long awaited sequel.');
      expect(details.isSeries, isFalse);
    });

    test('groups episodes into seasons', () {
      final details = parseDetails(
        html.parse(_seriesPageHtml),
        '/series/severance',
        ProviderKind.fourkhdhub,
      );

      expect(details.isSeries, isTrue);
      expect(details.seasons.map((e) => e.number), [1, 2]);
      expect(details.seasons.first.episodes.map((e) => e.number), [1, 2]);
    });
  });

  group('release parsing', () {
    test('keeps playable mirrors and rejects archives and plain http', () {
      final releases = parseReleases(html.parse(_moviePageHtml), ProviderKind.fourkhdhub);

      expect(releases, hasLength(1));
      expect(releases.single.mirrors.single.url, contains('pixeldrain.dev'));
      expect(releases.single.quality, '1080p');
      expect(releases.single.codec, 'hevc');
      expect(releases.single.sizeBytes, (3.4 * 1024 * 1024 * 1024).round());
    });

    test('attaches the referer the site requires', () {
      final releases = parseReleases(html.parse(_moviePageHtml), ProviderKind.fourkhdhub);
      expect(releases.single.mirrors.single.headers['Referer'], fourKHdHubBase);
    });

    test('filters episode releases to the requested episode', () {
      final releases = parseReleases(
        html.parse(_seriesPageHtml),
        ProviderKind.fourkhdhub,
        season: 1,
        episode: 2,
      );

      expect(releases, hasLength(1));
      expect(releases.single.mirrors.single.url, endsWith('s01e02.mkv'));
    });

    test('returns a whole season when no episode is given', () {
      final releases = parseReleases(
        html.parse(_seriesPageHtml),
        ProviderKind.fourkhdhub,
        season: 1,
      );
      expect(releases, hasLength(2));
    });
  });

  group('helpers', () {
    test('parse season and episode markers', () {
      expect(parseSeasonEpisode('Show.S01E02.mkv')?.season, 1);
      expect(parseSeasonEpisode('Show.S01E02.mkv')?.episode, 2);
      expect(parseSeasonEpisode('Show s2 e10')?.episode, 10);
      expect(parseSeasonEpisode('no marker here'), isNull);
    });

    test('reject unsafe mirrors', () {
      expect(isPlayableMirror('https://cdn.example/a.mkv'), isTrue);
      expect(isPlayableMirror('http://cdn.example/a.mkv'), isFalse);
      expect(isPlayableMirror('https://localhost/a.mkv'), isFalse);
      expect(isPlayableMirror('https://192.168.1.5/a.mkv'), isFalse);
      expect(isPlayableMirror('https://cdn.example/a.zip'), isFalse);
      expect(isPlayableMirror('https://cdn.example/login.php'), isFalse);
    });

    test('label mirrors by host', () {
      expect(mirrorLabel('https://pixeldrain.dev/api/file/x'), 'Pixeldrain');
      expect(mirrorLabel('https://cdn.example.com/x'), 'Example');
    });

    test('parse size labels', () {
      expect(parseSizeLabel('1 GB'), 1024 * 1024 * 1024);
      expect(parseSizeLabel('500 MB'), 500 * 1024 * 1024);
      expect(parseSizeLabel('2.5gb'), (2.5 * 1024 * 1024 * 1024).round());
      expect(parseSizeLabel('unknown'), isNull);
      expect(parseSizeLabel(null), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/metadata/cinemeta.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';
import 'package:vesper_movies/sources/source_matcher.dart';

CatalogItem _candidate(String title, {String? year, bool series = false}) {
  return CatalogItem(
    id: MediaId(ProviderKind.moviebox, title),
    title: title,
    mediaType: series ? MediaType.series : MediaType.movie,
    year: year,
  );
}

int _score(
  String wanted,
  String found, {
  String? wantedYear,
  String? foundYear,
  bool wantedSeries = false,
  bool foundSeries = false,
}) {
  return scoreCandidate(
    wantedTitle: wanted,
    wantedYear: wantedYear,
    wantedSeries: wantedSeries,
    candidate: _candidate(found, year: foundYear, series: foundSeries),
  );
}

void main() {
  group('title normalisation', () {
    test('strips punctuation and case', () {
      expect(normaliseTitle('Star Wars: The Mandalorian'), 'star wars the mandalorian');
      expect(normaliseTitle("Don't Look Back"), 'don t look back');
      expect(normaliseTitle('  Spaced   Out  '), 'spaced out');
    });

    test('keeps digits', () {
      expect(normaliseTitle('Practical Magic 2'), 'practical magic 2');
    });
  });

  group('scoring', () {
    test('rewards an exact title match', () {
      expect(_score('Mayday', 'Mayday'), greaterThan(SourceMatcher.minimumScore));
    });

    test('ignores punctuation differences', () {
      expect(_score('Spider-Man: No Way Home', 'Spider Man No Way Home'), greaterThan(100));
    });

    test('rewards a matching year and punishes a distant one', () {
      final exact = _score('Dune', 'Dune', wantedYear: '2021', foundYear: '2021');
      final near = _score('Dune', 'Dune', wantedYear: '2021', foundYear: '2022');
      final distant = _score('Dune', 'Dune', wantedYear: '2021', foundYear: '1984');

      expect(exact, greaterThan(near));
      expect(near, greaterThan(distant));
    });

    test('punishes a film matched against a series', () {
      final aligned = _score('Fargo', 'Fargo', wantedSeries: true, foundSeries: true);
      final crossed = _score('Fargo', 'Fargo', wantedSeries: true);

      expect(aligned, greaterThan(crossed));
      expect(crossed, lessThan(SourceMatcher.minimumScore));
    });

    test('rejects an unrelated title outright', () {
      expect(_score('Mayday', 'The Gentlemen'), 0);
      expect(_score('Reacher', 'Ted Lasso'), 0);
    });

    test('rejects a partial overlap that is mostly noise', () {
      expect(_score('The Whisper Man', 'The Invite'), lessThan(SourceMatcher.minimumScore));
    });

    test('accepts a prefixed release name', () {
      expect(
        _score('Practical Magic', 'Practical Magic 2'),
        greaterThanOrEqualTo(SourceMatcher.minimumScore),
      );
    });

    test('handles an empty candidate title', () {
      expect(_score('Mayday', ''), 0);
    });
  });

  group('episode extraction from cinemeta videos', () {
    test('groups videos into ordered seasons', () {
      final seasons = seasonsFromVideos({
        'videos': [
          {'season': 2, 'episode': 1, 'name': 'Second Season Opener'},
          {'season': 1, 'episode': 2, 'name': 'Two', 'overview': 'Second episode'},
          {'season': 1, 'episode': 1, 'name': 'One', 'thumbnail': 'https://e/1.jpg'},
        ],
      });

      expect(seasons.map((s) => s.number), [1, 2]);
      expect(seasons.first.episodes.map((e) => e.number), [1, 2]);
      expect(seasons.first.episodes.first.title, 'One');
      expect(seasons.first.episodes.first.stillUrl, 'https://e/1.jpg');
      expect(seasons.first.episodes.last.overview, 'Second episode');
      expect(seasons.first.episodes.first.label, 'S1E1');
    });

    test('drops specials and malformed entries', () {
      final seasons = seasonsFromVideos({
        'videos': [
          {'season': 0, 'episode': 1, 'name': 'Special'},
          {'season': 1, 'name': 'No episode number'},
          {'episode': 3, 'name': 'No season'},
          {'season': 1, 'episode': 1, 'name': 'Keep'},
          'not a map',
        ],
      });

      expect(seasons, hasLength(1));
      expect(seasons.single.episodes, hasLength(1));
      expect(seasons.single.episodes.single.title, 'Keep');
    });

    test('returns nothing when there are no videos', () {
      expect(seasonsFromVideos(const {}), isEmpty);
      expect(seasonsFromVideos(const {'videos': []}), isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/design/widgets/poster_card.dart';
import 'package:vesper_movies/metadata/cinemeta.dart';
import 'package:vesper_movies/metadata/metadata_source.dart';
import 'package:vesper_movies/metadata/tmdb.dart';
import 'package:vesper_movies/models/media.dart';

void main() {
  group('cinemeta catalogue entries', () {
    test('carry a poster, a year and a rating', () {
      final item = metaToCatalogItem({
        'id': 'tt28014327',
        'name': 'Mayday',
        'type': 'movie',
        'year': '2026',
        'poster': 'https://images.metahub.space/poster/small/tt28014327/img',
        'background':
            'https://images.metahub.space/background/medium/tt28014327/img',
        'imdbRating': '6.9',
      }, 'movie');

      expect(item, isNotNull);
      expect(item!.title, 'Mayday');
      expect(item.year, '2026');
      expect(item.posterUrl, contains('images.metahub.space'));
      expect(item.backdropUrl, isNotNull);
      expect(item.rating, 6.9);
      expect(item.mediaType, MediaType.movie);
    });

    test('recognise a series and its open ended year range', () {
      final item = metaToCatalogItem({
        'id': 'tt13210838',
        'name': 'The Gentlemen',
        'type': 'series',
        'year': '2024-',
        'poster': 'https://images.metahub.space/poster/small/tt13210838/img',
      }, 'movie');

      expect(item!.mediaType, MediaType.series);
      expect(item.year, '2024');
    });

    test('fall back to the requested type when the entry omits one', () {
      final item = metaToCatalogItem({
        'id': 'tt1',
        'name': 'Untyped',
      }, 'series');
      expect(item!.mediaType, MediaType.series);
    });

    test('drop entries with no id or no name', () {
      expect(metaToCatalogItem({'name': 'No id'}, 'movie'), isNull);
      expect(metaToCatalogItem({'id': 'tt1'}, 'movie'), isNull);
      expect(metaToCatalogItem('not a map', 'movie'), isNull);
    });
  });

  group('poster quality', () {
    test('upgrade metahub posters from small to medium', () {
      expect(
        upgradePosterUrl('https://images.metahub.space/poster/small/tt1/img'),
        'https://images.metahub.space/poster/medium/tt1/img',
      );
    });

    test('leave other hosts untouched', () {
      const tmdb = 'https://image.tmdb.org/t/p/w500/abc.jpg';
      expect(upgradePosterUrl(tmdb), tmdb);
    });
  });

  group('tmdb image urls', () {
    test('build sized urls and tolerate a missing path', () {
      expect(
        TmdbImage.poster('/abc.jpg'),
        'https://image.tmdb.org/t/p/w500/abc.jpg',
      );
      expect(
        TmdbImage.backdrop('/abc.jpg'),
        'https://image.tmdb.org/t/p/w1280/abc.jpg',
      );
      expect(TmdbImage.poster(null), isNull);
      expect(TmdbImage.poster(''), isNull);
    });
  });

  group('shelves', () {
    test('cover both films and series', () {
      final types = CatalogShelf.values.map((e) => e.type).toSet();
      expect(types, containsAll(<String>['movie', 'series']));
    });

    test('each carry a human title and a catalogue id', () {
      for (final shelf in CatalogShelf.values) {
        expect(shelf.title, isNotEmpty);
        expect(shelf.sort, isNotEmpty);
      }
    });
  });

  group('tmdb configuration', () {
    test('reports itself unconfigured without a key', () {
      expect(TmdbSource(apiKey: '').isConfigured, isFalse);
      expect(TmdbSource(apiKey: '   ').isConfigured, isFalse);
      expect(TmdbSource(apiKey: 'abc').isConfigured, isTrue);
    });

    test('returns nothing from a shelf when unconfigured', () async {
      final items = await TmdbSource(apiKey: '')
          .shelf(CatalogShelf.trendingMovies);
      expect(items, isEmpty);
    });
  });
}

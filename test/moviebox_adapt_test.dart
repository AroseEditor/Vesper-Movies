import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/release.dart';
import 'package:vesper_movies/sources/moviebox/adapt.dart';

const _policy =
    'eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9zYWNkbi5oYWt1bmF5bWF0YXRhLmNvbS9yZXNvdXJjZS'
    '9hYmMxMjMvKiIsIkNvbmRpdGlvbiI6eyJEYXRlTGVzc1RoYW4iOnsiQVdTOkVwb2NoVGltZSI6MTkwMDAwMDAwMH19fV19';

void main() {
  group('field readers tolerate mixed types', () {
    test('accept numbers where strings are expected', () {
      expect(readString({'id': 12345}, const ['id']), '12345');
      expect(readInt({'se': '2'}, const ['se']), 2);
      expect(readDouble({'rating': '8.4'}, const ['rating']), 8.4);
    });

    test('fall through a chain of alternative keys', () {
      expect(readString({'name': 'Dune'}, const ['title', 'name']), 'Dune');
      expect(readString({'title': '  '}, const ['title', 'name']), isNull);
    });

    test('return safe defaults for the wrong shape', () {
      expect(readString('not a map', const ['title']), isNull);
      expect(readList(null, const ['list']), isEmpty);
    });
  });

  group('year extraction', () {
    test('finds the first plausible four digit year', () {
      expect(extractYear('2025-03-14'), '2025');
      expect(extractYear('Released 1998 worldwide'), '1998');
      expect(extractYear('no year here'), '');
      expect(extractYear(null), '');
    });
  });

  group('poster resolution', () {
    test('prefers a flat url and falls back to a nested cover object', () {
      expect(readPoster({'coverUrl': 'https://img/a.jpg'}), 'https://img/a.jpg');
      expect(
        readPoster({
          'cover': {'url': 'https://img/b.jpg'},
        }),
        'https://img/b.jpg',
      );
      expect(readPoster({'title': 'x'}), isNull);
    });
  });

  group('search', () {
    test('reads the nested results shape', () {
      final items = searchJsonToCatalog({
        'results': [
          {
            'subjects': [
              {
                'subjectId': '1',
                'title': 'Dune',
                'subjectType': 1,
                'releaseDate': '2021-10-22',
                'coverUrl': 'https://img/dune.jpg',
              },
              {'subjectId': '2', 'title': 'Severance', 'subjectType': 2, 'seasonCount': 2},
            ],
          },
        ],
      });

      expect(items, hasLength(2));
      expect(items.first.title, 'Dune');
      expect(items.first.year, '2021');
      expect(items.first.mediaType, MediaType.movie);
      expect(items.last.mediaType, MediaType.series);
      expect(items.last.seasonCount, 2);
    });

    test('falls back to a flat list', () {
      final items = searchJsonToCatalog({
        'list': [
          {'id': '9', 'name': 'Arrival'},
        ],
      });

      expect(items, hasLength(1));
      expect(items.single.title, 'Arrival');
    });

    test('drops entries missing an id or a title and dedupes', () {
      final items = searchJsonToCatalog({
        'list': [
          {'id': '1', 'title': 'Keep'},
          {'id': '1', 'title': 'Duplicate'},
          {'title': 'No id'},
          {'id': '2'},
        ],
      });

      expect(items, hasLength(1));
      expect(items.single.title, 'Keep');
    });
  });

  group('homepage', () {
    test('harvests subjects from banners, custom data and plain lists', () {
      final items = homepageJsonToCatalog({
        'items': [
          {
            'banner': {
              'banners': [
                {
                  'subject': {'subjectId': 'a', 'title': 'Banner Title'},
                },
              ],
            },
          },
          {
            'customData': {
              'items': [
                {
                  'subject': {'subjectId': 'b', 'title': 'Custom Title'},
                },
              ],
            },
          },
          {
            'subjects': [
              {'subjectId': 'c', 'title': 'Plain Title'},
            ],
          },
        ],
      });

      expect(items.map((e) => e.title), ['Banner Title', 'Custom Title', 'Plain Title']);
    });
  });

  group('details', () {
    test('expands seasons from explicit episode numbers', () {
      final details = detailsJsonToMediaDetails({
        'subjectId': '10',
        'title': 'Severance',
        'subjectType': 2,
        'seasons': {
          'seasons': [
            {
              'se': 1,
              'episodeNumbers': [1, 2, 3],
            },
          ],
        },
      }, '10');

      expect(details.isSeries, isTrue);
      expect(details.seasons, hasLength(1));
      expect(details.seasons.single.episodes, hasLength(3));
      expect(details.seasons.single.episodes.last.label, 'S1E3');
    });

    test('expands seasons from a max episode count', () {
      final details = detailsJsonToMediaDetails({
        'subjectId': '11',
        'title': 'Show',
        'subjectType': 2,
        'seasons': {
          'seasons': [
            {'se': 2, 'maxEp': 4},
          ],
        },
      }, '11');

      expect(details.seasons.single.number, 2);
      expect(details.seasons.single.episodes.map((e) => e.number), [1, 2, 3, 4]);
    });

    test('maps alternate dubs to their own subject ids', () {
      final details = detailsJsonToMediaDetails({
        'subjectId': '12',
        'title': 'Film',
        'dubs': [
          {'subjectId': '12', 'lanName': 'English'},
          {'subjectId': '13', 'lanName': 'Hindi'},
          {'subjectId': '13', 'lanName': 'Duplicate'},
        ],
      }, '12');

      expect(details.dubs, hasLength(2));
      expect(details.hasAlternateAudio, isTrue);
      expect(details.dubs.last.mediaId, '13');
      expect(details.dubs.last.language, 'Hindi');
    });

    test('survives a payload with almost nothing in it', () {
      final details = detailsJsonToMediaDetails(const {}, 'fallback');

      expect(details.id.value, 'fallback');
      expect(details.title, 'Unknown');
      expect(details.seasons, isEmpty);
      expect(details.isSeries, isFalse);
    });
  });

  group('captions', () {
    test('drops junk, empty files and duplicates, and puts english first', () {
      final options = captionsJsonToOptions({
        'extCaptions': [
          {'lanName': 'Hindi', 'url': 'https://s/hi.srt', 'size': 4000},
          {'lanName': 'English', 'url': 'https://s/en.srt', 'size': 5000},
          {'lanName': 'Junk', 'url': 'https://s/aa348f2541d13ffe.srt'},
          {'lanName': 'Empty', 'url': 'https://s/empty.srt', 'size': 20},
          {'lanName': 'Dupe', 'url': 'https://s/hi.srt', 'size': 4000},
          {'lanName': 'NoUrl'},
        ],
      });

      expect(options.map((e) => e.name), ['English', 'Hindi']);
    });
  });

  group('caption discovery', () {
    const page = {
      'list': [
        {
          'resourceId': '111',
          'se': 1,
          'ep': 1,
          'extCaptions': [
            {'lanName': 'English', 'url': 'https://c/en.srt', 'size': 5000},
          ],
        },
        {
          'resourceId': '222',
          'se': 1,
          'ep': 2,
          'extCaptions': [
            {'lanName': 'Hindi', 'url': 'https://c/hi.srt', 'size': 5000},
          ],
        },
      ],
    };

    test('collects resource ids for the requested episode only', () {
      expect(resourceIdsFor(page, season: 1, episode: 2), ['222']);
      expect(resourceIdsFor(page, season: 1, episode: 1), ['111']);
    });

    test('collects every resource id for a film', () {
      expect(resourceIdsFor(page), ['111', '222']);
    });

    test('reads captions embedded in the resource entry', () {
      final options = inlineCaptionsFromResources(page, season: 1, episode: 2);
      expect(options, hasLength(1));
      expect(options.single.name, 'Hindi');
    });

    test('keeps one entry per language and puts english first', () {
      final sorted = sortCaptions(const [
        SubtitleOption(name: 'Hindi', url: 'https://c/hi-1.srt'),
        SubtitleOption(name: 'English', url: 'https://c/en-1.srt'),
        SubtitleOption(name: 'English', url: 'https://c/en-2.srt'),
        SubtitleOption(name: 'hindi ', url: 'https://c/hi-2.srt'),
      ]);

      expect(sorted.map((e) => e.name), ['English', 'Hindi']);
      expect(sorted.first.url, 'https://c/en-1.srt');
    });

    test('normalises language labels for comparison', () {
      expect(normaliseLanguage('English '), normaliseLanguage('english'));
      expect(normaliseLanguage('Portugues (BR)'), normaliseLanguage('portugues br'));
    });
  });

  group('play info', () {
    test('rebuilds the manifest from the cookie and attaches playback headers', () {
      final releases = playInfoJsonToReleases(
        {
          'streams': [
            {
              'url': 'https://macdn.aoneroom.com/other/notice.mp4',
              'signCookie': 'CloudFront-Policy=$_policy; CloudFront-Signature=sig',
              'resolution': 1080,
            },
          ],
        },
        season: 1,
        episode: 2,
        userAgent: 'test-agent',
      );

      expect(releases, hasLength(1));
      final mirror = releases.single.mirrors.single;
      expect(mirror.url, 'https://sacdn.hakunaymatata.com/resource/abc123/index.mpd');
      expect(mirror.headers['Referer'], 'https://sportslive.wine');
      expect(mirror.headers['User-Agent'], 'test-agent');
      expect(mirror.headers['Cookie'], contains('CloudFront-Policy='));
      expect(releases.single.quality, '1080p');
      expect(releases.single.season, 1);
      expect(releases.single.episode, 2);
    });

    test('skips a stream that only offers a deprecation notice', () {
      final releases = playInfoJsonToReleases(
        {
          'streams': [
            {'url': 'https://cdn/notice.mp4'},
          ],
        },
        season: 0,
        episode: 0,
        userAgent: 'ua',
      );

      expect(releases, isEmpty);
    });
  });

  group('resource releases', () {
    test('keeps only files for the requested episode', () {
      final releases = resourceJsonToReleases(
        {
          'list': [
            {'resourceLink': 'https://cdn/s1e1.mkv', 'se': 1, 'ep': 1, 'resolution': 720},
            {'resourceLink': 'https://cdn/s1e2.mkv', 'se': 1, 'ep': 2, 'resolution': 1080},
          ],
        },
        season: 1,
        episode: 2,
      );

      expect(releases, hasLength(1));
      expect(releases.single.mirrors.single.url, 'https://cdn/s1e2.mkv');
      expect(releases.single.mirrors.single.directFile, isTrue);
    });

    test('takes every file for a movie', () {
      final releases = resourceJsonToReleases(
        {
          'list': [
            {'url': 'https://cdn/a.mkv', 'resolution': 1080},
            {'url': 'https://cdn/b.mkv', 'resolution': 720},
          ],
        },
        season: 0,
        episode: 0,
      );

      expect(releases, hasLength(2));
    });
  });

  group('sorting', () {
    test('orders by resolution then by size', () {
      final sorted = sortReleases(
        resourceJsonToReleases(
          {
            'list': [
              {'url': 'https://cdn/a.mkv', 'resolution': 720, 'size': 100},
              {'url': 'https://cdn/b.mkv', 'resolution': 2160, 'size': 200},
              {'url': 'https://cdn/c.mkv', 'resolution': 1080, 'size': 900},
              {'url': 'https://cdn/d.mkv', 'resolution': 1080, 'size': 4000},
            ],
          },
          season: 0,
          episode: 0,
        ),
      );

      expect(sorted.map((e) => e.mirrors.single.url), [
        'https://cdn/b.mkv',
        'https://cdn/d.mkv',
        'https://cdn/c.mkv',
        'https://cdn/a.mkv',
      ]);
    });
  });
}

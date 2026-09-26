import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/metadata/tmdb.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/models/provider_kind.dart';

class _Fake implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    Object body = {};
    if (path.contains('/search/')) {
      body = {
        'results': [
          {
            'id': 77,
            'name': 'Hunkkaar',
            'media_type': 'tv',
            'first_air_date': '2026-01-01',
            'overview': 'text',
          },
        ],
      };
    } else if (path.endsWith('/tv/77')) {
      final append = options.queryParameters['append_to_response'] as String?;
      body = append == null
          ? {
              'seasons': [
                {'season_number': 0},
                {'season_number': 1},
              ],
            }
          : {
              'season/1': {
                'episodes': [
                  for (var i = 1; i <= 8; i++)
                    {'episode_number': i, 'name': 'Ep $i', 'air_date': '2026-02-0$i'},
                  {'episode_number': 9, 'name': 'Future', 'air_date': '2999-01-01'},
                ],
              },
            };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  test('tmdb fills in the episodes a catalogue is missing and hides unaired ones', () async {
    final dio = Dio()..httpClientAdapter = _Fake();
    final tmdb = TmdbSource(dio: dio, apiKey: 'key');
    const known = MediaDetails(
      id: MediaId(ProviderKind.addons, 'tt1'),
      title: 'Hunkkaar',
      mediaType: MediaType.series,
      year: '2026',
      seasons: [
        Season(number: 1, episodes: [Episode(season: 1, number: 1, title: 'Episode 1')]),
      ],
    );

    final result = await tmdb.describe(known);

    expect(result?.seasons, hasLength(1));
    expect(result!.seasons.first.episodes, hasLength(8));
    expect(result.seasons.first.episodes.first.title, 'Ep 1');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/moviebox/cloudfront.dart';
import 'package:vesper_movies/sources/moviebox/endpoints.dart';

const _policy =
    'eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9zYWNkbi5oYWt1bmF5bWF0YXRhLmNvbS9yZXNvdXJjZS'
    '9hYmMxMjMvKiIsIkNvbmRpdGlvbiI6eyJEYXRlTGVzc1RoYW4iOnsiQVdTOkVwb2NoVGltZSI6MTkwMDAwMDAwMH19fV19';

const _cookie =
    'CloudFront-Policy=$_policy; CloudFront-Signature=SIGVALUE~abc-def_; '
    'CloudFront-Key-Pair-Id=APKAEXAMPLE';

void main() {
  group('sign cookie', () {
    test('parses each cloudfront part', () {
      final parsed = parseSignCookie(_cookie);

      expect(parsed['CloudFront-Policy'], _policy);
      expect(parsed['CloudFront-Signature'], 'SIGVALUE~abc-def_');
      expect(parsed['CloudFront-Key-Pair-Id'], 'APKAEXAMPLE');
    });

    test('normalizes into a single header value', () {
      expect(
        normalizeSignCookie(
          'CloudFront-Policy=a;\nCloudFront-Signature=b ;  CloudFront-Key-Pair-Id=c',
        ),
        'CloudFront-Policy=a; CloudFront-Signature=b; CloudFront-Key-Pair-Id=c',
      );
    });

    test('ignores fragments without a value', () {
      expect(parseSignCookie('garbage; =novalue; Key=Value'), {'Key': 'Value'});
    });
  });

  group('manifest reconstruction', () {
    test('rebuilds the manifest url from the policy resource', () {
      expect(
        resolveDashManifestFromPolicy(_cookie),
        'https://sacdn.hakunaymatata.com/resource/abc123/index.mpd',
      );
    });

    test('undoes the cloudfront base64 alphabet', () {
      expect(
        decodeCloudFrontPolicy(_policy),
        contains('sacdn.hakunaymatata.com'),
      );
    });

    test('returns nothing when there is no policy', () {
      expect(
        resolveDashManifestFromPolicy('CloudFront-Key-Pair-Id=APKAEXAMPLE'),
        isNull,
      );
      expect(resolveDashManifestFromPolicy(''), isNull);
    });

    test('rejects a resource that is not an http url', () {
      expect(
        resolveDashManifestFromPolicy('CloudFront-Policy=bm90anNvbg'),
        isNull,
      );
    });
  });

  group('edge cache cookies', () {
    const edgeCookie =
        'Edge-Cache-Cookie=urlprefix=aHR0cHM6Ly9zYmNkbjMuaGFrdW5heW1hdGF0YS5jb20vZGFzaC8xMTExNzc0'
        'NTc1OTg3MjQ1MTUyXzBfMF8xMDgwX2gyNjVfMzE3Lw:sign=8e620659c940c3e249f94f5bec72844c:'
        't=1789949208';

    test('rebuild the manifest from the url prefix', () {
      expect(
        resolveEdgeCacheManifest(edgeCookie),
        'https://sbcdn3.hakunaymatata.com/dash/1111774575987245152_0_0_1080_h265_317/index.mpd',
      );
    });

    test('are resolved by the combined signed manifest helper', () {
      expect(resolveSignedManifest(edgeCookie), endsWith('/index.mpd'));
      expect(resolveSignedManifest(_cookie), endsWith('/index.mpd'));
    });

    test('win over a deprecation notice url', () {
      expect(
        resolveStreamUrl(
          signCookie: edgeCookie,
          fallbackUrl: 'https://macdn.aoneroom.com/other/2026/09/04/b164fbfb4347792950bdfbfb563d39d9.mp4',
        ),
        startsWith('https://sbcdn3.hakunaymatata.com/dash/'),
      );
    });

    test('survive a malformed prefix', () {
      expect(
        resolveEdgeCacheManifest('Edge-Cache-Cookie=urlprefix=!!!:sign=x'),
        isNull,
      );
      expect(resolveEdgeCacheManifest('Edge-Cache-Cookie=sign=x:t=1'), isNull);
      expect(resolveEdgeCacheManifest('Other-Cookie=urlprefix=abc'), isNull);
    });

    test('are passed through to the player as a single header value', () {
      expect(
        normalizeSignCookie(edgeCookie),
        startsWith('Edge-Cache-Cookie=urlprefix='),
      );
      expect(normalizeSignCookie(edgeCookie), contains(':sign='));
    });
  });

  group('deprecation notices', () {
    test('rejects the known notice files', () {
      expect(
        isDeprecationNoticeUrl(
          'https://cdn.example.com/1c7de0bd3393702d9191801f15f88f8d.mp4',
        ),
        isTrue,
      );
      expect(
        isDeprecationNoticeUrl(
          'https://cdn.example.com/9a0461bc39da389663bf3dbb17091d3f.mp4',
        ),
        isTrue,
      );
      expect(
        isDeprecationNoticeUrl(
          'https://cdn.example.com/b164fbfb4347792950bdfbfb563d39d9.mp4',
        ),
        isTrue,
      );
    });

    test('rejects notice paths and the other bucket', () {
      expect(
        isDeprecationNoticeUrl('https://cdn.example.com/notice.mp4'),
        isTrue,
      );
      expect(
        isDeprecationNoticeUrl('https://macdn.aoneroom.com/other/clip.mp4'),
        isTrue,
      );
    });

    test('keeps a genuine stream url', () {
      expect(
        isDeprecationNoticeUrl(
          'https://sacdn.hakunaymatata.com/r/abc/index.mpd',
        ),
        isFalse,
      );
    });
  });

  group('stream resolution', () {
    test('prefers the policy manifest over the advertised url', () {
      expect(
        resolveStreamUrl(
          signCookie: _cookie,
          fallbackUrl: 'https://macdn.aoneroom.com/other/notice.mp4',
        ),
        'https://sacdn.hakunaymatata.com/resource/abc123/index.mpd',
      );
    });

    test('falls back to the advertised url when it is genuine', () {
      expect(
        resolveStreamUrl(
          signCookie: null,
          fallbackUrl: 'https://cdn.example.com/movie.mp4',
        ),
        'https://cdn.example.com/movie.mp4',
      );
    });

    test('yields nothing when the only candidate is a notice', () {
      expect(
        resolveStreamUrl(
          signCookie: '',
          fallbackUrl: 'https://cdn.example.com/notice.mp4',
        ),
        isNull,
      );
    });
  });

  group('endpoints', () {
    test('omits season and episode for a film', () {
      expect(
        MovieBoxEndpoints.playInfo('123'),
        '/wefeed-mobile-bff/subject-api/play-info/v2?subjectId=123',
      );
    });

    test('includes season and episode for a series', () {
      expect(
        MovieBoxEndpoints.playInfo('123', season: 2, episode: 5),
        '/wefeed-mobile-bff/subject-api/play-info/v2?subjectId=123&se=2&ep=5',
      );
    });

    test('builds the resource path the reference builds', () {
      expect(
        MovieBoxEndpoints.resource('12345'),
        '/wefeed-mobile-bff/subject-api/resource?subjectId=12345&page=1&perPage=20',
      );
      expect(
        MovieBoxEndpoints.resource('67890', season: 2, episode: 5),
        '/wefeed-mobile-bff/subject-api/resource?subjectId=67890&se=2&ep=5&page=1&perPage=20',
      );
      expect(
        MovieBoxEndpoints.resource(
          '67890',
          season: 1,
          episode: 10,
          page: 2,
          resolution: 1080,
        ),
        '/wefeed-mobile-bff/subject-api/resource?subjectId=67890&se=1&ep=10&page=2&perPage=20'
        '&resolution=1080',
      );
    });

    test('pages episodes in blocks of twenty', () {
      expect(MovieBoxEndpoints.pageForEpisode(0), 1);
      expect(MovieBoxEndpoints.pageForEpisode(1), 1);
      expect(MovieBoxEndpoints.pageForEpisode(20), 1);
      expect(MovieBoxEndpoints.pageForEpisode(21), 2);
      expect(MovieBoxEndpoints.pageForEpisode(41), 3);
    });

    test('sends the search body the api expects', () {
      expect(MovieBoxEndpoints.searchBody('dune', 2), {
        'keyword': 'dune',
        'page': 2,
        'perPage': 15,
        'subjectType': 0,
      });
    });
  });
}

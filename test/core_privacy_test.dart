import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/core/errors.dart';
import 'package:vesper_movies/core/redact.dart';
import 'package:vesper_movies/models/provider_kind.dart';

void main() {
  group('source errors never carry a url', () {
    test('every variant stringifies without a scheme separator', () {
      const errors = <SourceError>[
        NetworkError('connection_failed'),
        NetworkError('timeout', timedOut: true),
        RateLimited(30),
        RateLimited(),
        NotFound(),
        ParseError('search'),
        Unavailable(502),
        Unavailable(),
        Cancelled(),
      ];

      for (final error in errors) {
        expect(error.toString(), isNot(contains('://')));
      }
    });

    test('user messages name the source without leaking the query', () {
      expect(
        const NetworkError('x').userMessage(ProviderKind.circleftp),
        'CircleFTP needs a BDIX connection.',
      );
      expect(
        const NetworkError('x', timedOut: true).userMessage(ProviderKind.moviebox),
        'MovieBox timed out.',
      );
      expect(
        const NetworkError('x').userMessage(ProviderKind.fourkhdhub),
        'Cannot reach 4KHDHub.',
      );
      expect(const RateLimited(30).userMessage(ProviderKind.moviebox), 'Rate limited. Wait 30s.');
      expect(const NotFound().userMessage(ProviderKind.moviebox), 'No results found.');
      expect(const Unavailable(502).userMessage(ProviderKind.fourkhdhub), '4KHDHub error (502).');
    });
  });

  group('redaction', () {
    test('urls keep only scheme and host', () {
      expect(redactUrl('https://api.example.com/search?q=secret+title'), 'https://api.example.com');
      expect(redactUrl('http://1.2.3.4:5000/api/posts?searchTerm=dune'), 'http://1.2.3.4');
      expect(redactUrl('not a url'), '[redacted]');
    });

    test('paths lose the user directory', () {
      expect(redactPath(r'C:\Users\someone\AppData\vesper'), '~/AppData/vesper');
      expect(redactPath('/home/someone/.local/share/vesper'), '~/.local/share/vesper');
      expect(redactPath('/opt/vesper'), '/opt/vesper');
    });

    test('playlists are described by size, never by url', () {
      expect(describePlaylist(1200), 'playlist(1200 channels)');
    });
  });

  group('provider kinds', () {
    test('resolve by id and by legacy alias', () {
      expect(ProviderKind.byId('moviebox'), ProviderKind.moviebox);
      expect(ProviderKind.byId('4khdhub'), ProviderKind.fourkhdhub);
      expect(ProviderKind.byId('bdix_circle_ftp'), ProviderKind.circleftp);
      expect(ProviderKind.byId('nope'), isNull);
    });

    test('bdix sources are flagged as local network', () {
      expect(ProviderKind.circleftp.isBdix, isTrue);
      expect(ProviderKind.dhakaflix.isLocalNetwork, isTrue);
      expect(ProviderKind.moviebox.isBdix, isFalse);
    });
  });
}

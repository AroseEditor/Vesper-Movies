import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/moviebox/crypto.dart';

const _ts = 1700000000000;
const _getUrl =
    'https://api6.aoneroom.com/wefeed-mobile-bff/subject-api/get?subjectId=12345';
const _postUrl =
    'https://api6.aoneroom.com/wefeed-mobile-bff/subject-api/search/v2';
const _body = '{"keyword":"dune","page":1}';

void main() {
  group('md5', () {
    test('matches the reference digests', () {
      expect(md5Hex(utf8.encode('')), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(md5Hex(utf8.encode(_body)), 'f3663777171f53fcb5443007c6344365');
    });
  });

  group('client token', () {
    test('is the timestamp plus the md5 of its reversed text', () {
      expect(
        generateClientToken(_ts),
        '1700000000000,e41bb805cc23fdc5541917da93d608d5',
      );
    });

    test('splits into exactly two parts with a 32 character digest', () {
      final parts = generateClientToken(_ts).split(',');
      expect(parts, hasLength(2));
      expect(parts.first, '1700000000000');
      expect(parts.last.length, 32);
    });
  });

  group('canonical query', () {
    test('sorts keys and preserves the order of repeated values', () {
      expect(
        sortedQueryString('https://api.example.com/e?b=2&a=1&c=3&a=0'),
        'a=1&a=0&b=2&c=3',
      );
    });

    test('decodes percent escapes before signing', () {
      expect(
        sortedQueryString('https://api.example.com/e?q=a%20b&z=1'),
        'q=a b&z=1',
      );
    });

    test('is empty when there is no query', () {
      expect(sortedQueryString('https://api.example.com/endpoint'), '');
    });
  });

  group('canonical string', () {
    test('leaves body length and body hash empty for a get', () {
      final canonical = buildCanonicalString(
        method: 'GET',
        url: _getUrl,
        timestampMs: _ts,
        accept: 'application/json',
        contentType: 'application/json',
      );

      expect(
        canonical.replaceAll('\n', '<LF>'),
        'GET<LF>application/json<LF>application/json<LF><LF>1700000000000<LF><LF>'
        '/wefeed-mobile-bff/subject-api/get?subjectId=12345',
      );
    });

    test('carries byte length and body digest for a post', () {
      final canonical = buildCanonicalString(
        method: 'POST',
        url: _postUrl,
        timestampMs: _ts,
        accept: 'application/json',
        contentType: 'application/json',
        body: _body,
      );

      expect(
        canonical.replaceAll('\n', '<LF>'),
        'POST<LF>application/json<LF>application/json<LF>27<LF>1700000000000<LF>'
        'f3663777171f53fcb5443007c6344365<LF>/wefeed-mobile-bff/subject-api/search/v2',
      );
    });
  });

  group('signature', () {
    test('matches the reference for a get', () {
      expect(
        generateSignature(
          method: 'GET',
          url: _getUrl,
          timestampMs: _ts,
          accept: 'application/json',
          contentType: 'application/json',
        ),
        '1700000000000|2|UiEtOwIuVN55aHV4IZMKdg==',
      );
    });

    test('matches the reference for a post', () {
      expect(
        generateSignature(
          method: 'POST',
          url: _postUrl,
          timestampMs: _ts,
          accept: 'application/json',
          contentType: 'application/json',
          body: _body,
        ),
        '1700000000000|2|WpG6bOXfU46qCRltp5n8Jw==',
      );
    });
  });

  group('signed headers', () {
    test('use one timestamp for both the token and the signature', () {
      final identity = DeviceIdentity.generate();
      final headers = buildSignedHeaders(
        method: 'GET',
        url: _getUrl,
        identity: identity,
        timestampMs: _ts,
      );

      expect(headers['x-client-token']!.split(',').first, '1700000000000');
      expect(headers['x-tr-signature']!.split('|').first, '1700000000000');
      expect(
        headers['x-tr-signature'],
        '1700000000000|2|UiEtOwIuVN55aHV4IZMKdg==',
      );
    });

    test('omit authorization until a session exists', () {
      final identity = DeviceIdentity.generate();

      final anonymous = buildSignedHeaders(
        method: 'POST',
        url: _postUrl,
        identity: identity,
        timestampMs: _ts,
      );
      expect(anonymous.containsKey('Authorization'), isFalse);

      final authenticated = buildSignedHeaders(
        method: 'POST',
        url: _postUrl,
        identity: identity,
        authToken: 'jwt-token',
        timestampMs: _ts,
      );
      expect(authenticated['Authorization'], 'Bearer jwt-token');
    });
  });

  group('device identity', () {
    test('impersonates the reference client shape', () {
      final identity = DeviceIdentity.generate();

      expect(identity.userAgent, contains('com.community.oneroom/500201'));
      expect(identity.userAgent, contains('Cronet/135.0.7012.3'));

      final info = jsonDecode(identity.clientInfo) as Map<String, dynamic>;
      expect(info['package_name'], 'com.community.oneroom');
      expect(info['version_name'], '4.0.01.0813.03');
      expect(info['sp_code'], '40401');
      expect(info['X-Play-Mode'], '2');
      expect(info['version_code'], inInclusiveRange(50020117, 50020121));
      expect((info['device_id'] as String).length, 32);
    });

    test('derives nothing from the host machine', () {
      final info = jsonDecode(
        DeviceIdentity.generate().clientInfo,
      ) as Map<String, dynamic>;
      expect(info['brand'], 'Redmi');
      expect(info['os'], 'Android');
      expect(info.containsKey('hostname'), isFalse);
      expect(info.containsKey('username'), isFalse);
    });
  });
}

@Tags(['live'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/core/secure_dns.dart';

void main() {
  test('resolves over https dns and serves requests through it', () async {
    HttpOverrides.global = SecureDnsHttpOverrides();

    for (final host in ['api.themoviedb.org', 'v3-cinemeta.strem.io', 'api.github.com']) {
      final addresses = await SecureDns.instance.resolve(host);
      debugPrint('PROBE dns $host -> ${addresses.map((a) => a.address).join(', ')}');
      expect(addresses, isNotEmpty);
    }

    final dio = Dio();
    final cinemeta = await dio.get<dynamic>('https://v3-cinemeta.strem.io/catalog/movie/top.json');
    debugPrint('PROBE cinemeta ${cinemeta.statusCode}');
    final github = await dio.get<dynamic>(
      'https://api.github.com/repos/AroseEditor/Vesper-Movies/releases/latest',
    );
    debugPrint('PROBE github ${github.statusCode} ${github.data['tag_name']}');
    expect(cinemeta.statusCode, 200);

    final tunnel = (await StreamTunnel.start())!;
    debugPrint('PROBE tunnel ${tunnel.proxyUrl}');
    for (final url in ['https://v3-cinemeta.strem.io/manifest.json', 'http://example.com/']) {
      final result = await Process.run('curl', [
        '-s',
        '-o',
        'NUL',
        '-w',
        '%{http_code}',
        '-L',
        '-x',
        tunnel.proxyUrl,
        url,
      ]);
      debugPrint('PROBE curl via tunnel $url -> ${result.stdout}');
      expect('${result.stdout}', '200');
    }

    final big = await Process.run('curl', [
      '-s',
      '-o',
      'NUL',
      '-w',
      '%{http_code} %{size_download} %{speed_download}',
      '-x',
      tunnel.proxyUrl,
      'https://speed.cloudflare.com/__down?bytes=60000000',
    ]);
    debugPrint('PROBE big download via tunnel -> ${big.stdout}');
    final parts = '${big.stdout}'.split(' ');
    expect(parts.first, '200');
    expect(int.parse(parts[1]), 60000000);
  }, timeout: const Timeout(Duration(seconds: 90)));
}

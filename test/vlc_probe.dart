@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/links/link_source.dart';
import 'package:vesper_movies/sources/links/sites/hdhub4u_source.dart';
import 'package:vesper_movies/sources/links/web.dart';

void main() {
  test('vlc can read a resolved stream', () async {
    final source = HdHub4uSource(Web());
    final releases = await source.find(
      const LinkQuery(title: 'War 2', imdbId: 'tt27425164', year: '2025'),
    );
    final playback = await source.resolve(releases.first);
    debugPrint('PROBE url host ${originOf(playback.url)}');
    final result = await Process.run(r'C:\Program Files\VideoLAN\VLC\vlc.exe', [
      '-I',
      'dummy',
      '--vout',
      'dummy',
      '--aout',
      'dummy',
      '--run-time',
      '8',
      '--verbose',
      '1',
      playback.url,
      if (playback.headers['User-Agent'] != null)
        '--http-user-agent=${playback.headers['User-Agent']}',
      'vlc://quit',
    ]).timeout(const Duration(seconds: 60));
    final log = '${result.stdout}${result.stderr}';
    debugPrint('PROBE vlc exit ${result.exitCode}');
    debugPrint(
      'PROBE vlc errors: ${log.split('\n').where((l) => l.contains('error')).take(5).join(' | ')}',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

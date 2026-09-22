@Tags(['live'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/links/hosts.dart';
import 'package:vesper_movies/sources/links/web.dart';

const _links = {
  'hubdrive': 'https://hubdrive.pics/file/4090369360',
  'greenmotors': 'https://greenmotors.club/?id=UUtUUFNjaFBQR0xaNUx4bzBwcHk3MmszWjhab3hPRmZFZHVMN1NSbVlPc1UrY05mQkpmU1MrdUdMZzNsZ2dJc2MyQXpJVENjU21QTGt2Zk9ocUErY3hLTThtam9Ua0NtYVhtVnVqRktoczg9',
  'hubcdn': 'https://hubcdn.club/file/7SOgF1sgYW8gGhEniDWiR9v0Q',
  'molop': 'https://molop.art/watch?v=UL41PG5S',
  'm4ulinks': 'https://m4ulinks.site/number/42184',
  'filescab': 'https://filescab.sbs/movie/1187/',
  'm4uplay': 'https://m4uplay.store/file/2xms5aat14kq',
  'gate': 'https://leechpro.blog/archives/32133',
};

void main() {
  test('resolves each host chain to playable files', () async {
    final web = Web();
    final resolver = HostResolver(web);

    for (final entry in _links.entries) {
      var url = entry.value;
      if (entry.key == 'gate') {
        final page = await web.get(url);
        url =
            RegExp(r'https://cloud\.unblockedgames\.world/\?sid=[^"]+')
                .firstMatch(page.body)
                ?.group(0) ??
            '';
      }
      final started = DateTime.now();
      final files = await resolver.resolve(url, referer: 'https://hdmovie2a.live/');
      final ms = DateTime.now().difference(started).inMilliseconds;
      debugPrint('PROBE ${entry.key}: ${files.length} files in ${ms}ms');
      for (final file in files.take(3)) {
        debugPrint(
          'PROBE   [${file.server}] ${file.name ?? ''} ${file.size ?? ''} ${originOf(file.url)}',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

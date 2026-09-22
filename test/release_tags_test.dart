import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/sources/links/release_tags.dart';

void main() {
  test('reads quality, size, codec, language and rip from release names', () {
    final a = parseReleaseTags('720p x264 [1.61GB] War 2 (2025) DS4K WEB-DL [Hindi DD5.1]');
    expect(a.quality, '720p');
    expect(a.codec, 'x264');
    expect(a.language, 'Hindi');
    expect(a.rip, 'WEB-DL');
    expect(a.sizeBytes, (1.61 * 1024 * 1024 * 1024).round());

    final b = parseReleaseTags('Batwara 1947 (2026) Hindi Movie HDTC 480p.mkv');
    expect(b.rip, 'HDTC');
    expect(b.isCam, isTrue);

    final c = parseReleaseTags('Movie.2024.2160p.BluRay.REMUX.HEVC.10bit.Hindi.English.Tamil');
    expect(c.quality, '2160p');
    expect(c.language, startsWith('Multi'));
    expect(c.codec, contains('HEVC'));

    expect(parseReleaseTags('4K [2160p SDR WEB-DL 17.78GB]').quality, '2160p');
    expect(hasHindi('Hindi + English'), isTrue);
    expect(hasHindi('English'), isFalse);
  });
}

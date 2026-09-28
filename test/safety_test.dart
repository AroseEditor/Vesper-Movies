import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/core/safety.dart';
import 'package:vesper_movies/models/release.dart';

void main() {
  test('flags executables and installers disguised as media links', () {
    expect(isDangerousUrl('https://host.com/movie.exe'), isTrue);
    expect(isDangerousUrl('https://host.com/app.apk?token=1'), isTrue);
    expect(isDangerousUrl('https://host.com/setup.MSI'), isTrue);
    expect(isDangerousUrl('https://host.com/movie.mkv'), isFalse);
    expect(isDangerousUrl('https://host.com/stream.m3u8'), isFalse);
    expect(isDangerousUrl('https://host.com/no-extension'), isFalse);
  });

  test('drops dangerous subtitle links while keeping safe ones', () {
    final subtitles = safeSubtitles(const [
      SubtitleOption(name: 'English', url: 'https://host.com/sub.srt'),
      SubtitleOption(name: 'Payload', url: 'https://host.com/sub.exe'),
    ]);
    expect(subtitles, hasLength(1));
    expect(subtitles.single.name, 'English');
  });
}

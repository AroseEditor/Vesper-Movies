import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/player/player_controller.dart';

void main() {
  test('only real open failures end a stream attempt', () {
    expect(isFatalPlaybackError('Failed to open https://cdn.example/video.mkv.'), isTrue);
    expect(isFatalPlaybackError('Failed to recognize file format.'), isTrue);
    expect(isFatalPlaybackError('Exiting... (Errors when loading file)'), isTrue);

    expect(isFatalPlaybackError('Could not open/initialize audio device -> no sound.'), isFalse);
    expect(
      isFatalPlaybackError('Can not open external file https://subs.example/en.srt.'),
      isFalse,
    );
    expect(isFatalPlaybackError('tcp: Connection to tcp://cdn.example:443 failed'), isFalse);
  });
}

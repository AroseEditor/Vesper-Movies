import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/storage/library_store.dart';

WatchEntry _entry(int season, int episode, int updatedAt, {String id = 'tt1'}) => WatchEntry(
  id: id,
  title: 'Show',
  mediaType: MediaType.series,
  season: season,
  episode: episode,
  positionMs: 100,
  durationMs: 1000,
  updatedAt: updatedAt,
);

void main() {
  test('last episode is the most recently watched one for that title', () {
    final data = LibraryData(
      history: [
        _entry(1, 2, 10),
        _entry(2, 3, 30),
        _entry(1, 5, 20),
        _entry(4, 1, 99, id: 'tt2'),
      ],
    );

    final last = data.lastEpisodeOf('tt1');
    expect(last?.season, 2);
    expect(last?.episode, 3);
  });

  test('no episode history returns null', () {
    expect(const LibraryData().lastEpisodeOf('tt1'), isNull);
  });
}

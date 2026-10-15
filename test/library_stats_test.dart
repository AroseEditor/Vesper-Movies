import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/models/media.dart';
import 'package:vesper_movies/storage/library_store.dart';

WatchEntry _entry({
  required String id,
  int season = 0,
  int episode = 0,
  int positionMs = 0,
  bool completed = false,
}) => WatchEntry(
  id: id,
  title: id,
  mediaType: season > 0 ? MediaType.series : MediaType.movie,
  season: season,
  episode: episode,
  positionMs: positionMs,
  durationMs: positionMs + 1,
  completed: completed,
);

void main() {
  test('sums watch time and counts completed movies and episodes separately', () {
    final data = LibraryData(
      history: [
        _entry(id: 'movie-1', positionMs: 3600000, completed: true),
        _entry(id: 'show-1', season: 1, episode: 1, positionMs: 1200000, completed: true),
        _entry(id: 'show-1', season: 1, episode: 2, positionMs: 1200000, completed: true),
        _entry(id: 'movie-2', positionMs: 600000),
      ],
    );

    final stats = computeLibraryStats(data);
    expect(stats.watchTime, const Duration(milliseconds: 3600000 + 1200000 + 1200000 + 600000));
    expect(stats.moviesCompleted, 1);
    expect(stats.episodesCompleted, 2);
    expect(stats.titlesWatched, 3);
  });

  test('reports no stats for an empty library', () {
    final stats = computeLibraryStats(const LibraryData());
    expect(stats.watchTime, Duration.zero);
    expect(stats.titlesWatched, 0);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../models/media.dart';
import '../../models/release.dart';
import '../../player/player_controller.dart';
import '../../player/subtitle_style.dart';
import '../../sources/registry.dart';
import '../../sources/source_matcher.dart';
import '../../storage/library_controller.dart';
import 'details_controller.dart';

const _maxAttempts = 5;
const _playableTimeout = Duration(seconds: 50);

class PlaybackSession {
  const PlaybackSession({
    required this.item,
    required this.title,
    required this.matches,
    this.seasons = const [],
    this.season = 0,
    this.episode = 0,
    this.releases = const [],
    this.current,
    this.switching = false,
  });

  final CatalogItem item;
  final String title;
  final List<SourceMatch> matches;
  final List<Season> seasons;
  final int season;
  final int episode;
  final List<Release> releases;
  final Release? current;
  final bool switching;

  bool get isEpisode => season > 0;

  String get episodeLabel => isEpisode ? 'S${season}E$episode' : '';

  Episode? get currentEpisode => _find(season, episode);

  Episode? get nextEpisode {
    if (!isEpisode) return null;
    for (var i = 0; i < seasons.length; i++) {
      if (seasons[i].number != season) continue;
      final episodes = seasons[i].episodes;
      for (var j = 0; j < episodes.length; j++) {
        if (episodes[j].number != episode) continue;
        if (j + 1 < episodes.length) return episodes[j + 1];
        if (i + 1 < seasons.length && seasons[i + 1].episodes.isNotEmpty) {
          return seasons[i + 1].episodes.first;
        }
        return null;
      }
    }
    return null;
  }

  Episode? _find(int seasonNo, int episodeNo) {
    for (final entry in seasons) {
      if (entry.number != seasonNo) continue;
      for (final ep in entry.episodes) {
        if (ep.number == episodeNo) return ep;
      }
    }
    return null;
  }

  PlaybackSession copyWith({
    int? season,
    int? episode,
    List<Release>? releases,
    Release? current,
    bool clearCurrent = false,
    bool? switching,
  }) {
    return PlaybackSession(
      item: item,
      title: title,
      matches: matches,
      seasons: seasons,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      releases: releases ?? this.releases,
      current: clearCurrent ? null : (current ?? this.current),
      switching: switching ?? this.switching,
    );
  }
}

int _phoneRank(Release release) {
  final quality = (release.quality ?? '').toLowerCase();
  final height = int.tryParse(RegExp(r'(\d{3,4})p').firstMatch(quality)?.group(1) ?? '');
  if (quality.contains('4k') || quality.contains('uhd') || (height != null && height > 1080)) {
    return 3;
  }
  if (height == 1080) return 0;
  if (height == 720) return 1;
  return 2;
}

List<Release> rankForPhone(List<Release> releases) {
  final indexed = [for (var i = 0; i < releases.length; i++) (i, releases[i])];
  indexed.sort((a, b) {
    final byRank = _phoneRank(a.$2).compareTo(_phoneRank(b.$2));
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

class PlaybackSessionNotifier extends Notifier<PlaybackSession?> {
  int _generation = 0;

  @override
  PlaybackSession? build() => null;

  PlayerControllerNotifier get _player => ref.read(playerControllerProvider.notifier);

  Future<void> start({
    required CatalogItem item,
    required String title,
    required List<SourceMatch> matches,
    List<Season> seasons = const [],
    int season = 0,
    int episode = 0,
    Release? preferred,
  }) async {
    final generation = ++_generation;
    state = PlaybackSession(
      item: item,
      title: title,
      matches: matches,
      seasons: seasons,
      season: season,
      episode: episode,
    );

    _player.beginOpening();
    await _player.applySubtitleStyle(ref.read(subtitleDefaultsProvider));
    await _openEpisode(generation, preferred: preferred, startAt: _resumePoint());
  }

  Future<bool> playNext() async {
    final session = state;
    final next = session?.nextEpisode;
    if (session == null || next == null) return false;

    final generation = ++_generation;
    state = session.copyWith(
      season: next.season,
      episode: next.number,
      releases: const [],
      clearCurrent: true,
    );

    _player.beginOpening();
    await _openEpisode(generation, startAt: _resumePoint());
    return true;
  }

  Future<void> switchTo(Release release) async {
    final session = state;
    if (session == null || release == session.current) return;

    final generation = ++_generation;
    final position = _player.player.state.position;
    state = session.copyWith(switching: true);

    final ok = await _tryRelease(generation, release, position);
    if (generation != _generation) return;
    state = state?.copyWith(switching: false);
    if (!ok) _player.fail('That stream would not start. Pick another one from the cloud menu.');
  }

  void recordProgress(Duration position, Duration duration, bool completed) {
    final session = state;
    if (session == null) return;
    unawaited(
      ref
          .read(libraryProvider.notifier)
          .recordProgress(
            item: session.item,
            position: position,
            duration: duration,
            season: session.season,
            episode: session.episode,
            completed: completed,
          ),
    );
  }

  void end() {
    _generation++;
    state = null;
  }

  Duration _resumePoint() {
    final session = state;
    if (session == null) return Duration.zero;
    final saved = ref
        .read(libraryProvider)
        .value
        ?.entryFor(session.item.id.value, season: session.season, episode: session.episode);
    return saved != null && saved.isInProgress ? saved.resumeAt : Duration.zero;
  }

  Future<void> _openEpisode(int generation, {Release? preferred, Duration? startAt}) async {
    final session = state;
    if (session == null) return;

    List<Release> releases;
    try {
      releases = await gatherReleases(
        ref,
        EpisodeRef(session.matches, session.item, season: session.season, episode: session.episode),
      );
    } on Object catch (error) {
      debugPrint('gathering streams failed: $error');
      releases = const [];
    }
    debugPrint('streams found: ${releases.length}');
    if (generation != _generation) return;

    final ranked = Platform.isAndroid ? rankForPhone(releases) : releases;
    final ordered = [
      ?preferred,
      for (final release in ranked)
        if (release != preferred) release,
    ];
    state = state?.copyWith(releases: ordered);

    if (ordered.isEmpty) {
      _player.fail('No streams were found for this title.');
      return;
    }

    for (final release in ordered.take(_maxAttempts)) {
      if (generation != _generation) return;
      if (await _tryRelease(generation, release, startAt ?? Duration.zero)) return;
    }

    if (generation == _generation) {
      _player.fail('None of the streams would start. Open the cloud menu to try another source.');
    }
  }

  Future<bool> _tryRelease(int generation, Release release, Duration startAt) async {
    final session = state;
    if (session == null) return false;

    SourceMatch? match;
    for (final candidate in session.matches) {
      if (candidate.kind == release.kind) match = candidate;
    }

    try {
      final target = await resolvePlayback(
        ref.read(sourceRegistryProvider),
        PlaybackRequest(
          release: release,
          match: match,
          title: session.title,
          subtitle: session.isEpisode ? session.episodeLabel : null,
          season: session.season,
          episode: session.episode,
        ),
      );
      if (generation != _generation) return false;

      await _player.load(
        PlaybackTarget(
          source: target.source,
          title: target.title,
          subtitle: target.subtitle,
          startAt: startAt,
          season: target.season,
          episode: target.episode,
          mediaId: target.mediaId,
        ),
      );
      if (generation != _generation) {
        if (state == null) await _player.stop();
        return false;
      }

      final playable = await _player.waitUntilPlayable(_playableTimeout);
      debugPrint('stream attempt ${release.kind.id} ${playable ? 'playing' : 'did not start'}');
      if (!playable || generation != _generation) return false;

      state = state?.copyWith(current: release);
      unawaited(_player.applyPreferredTracks());
      return true;
    } on SourceError catch (error) {
      debugPrint('stream attempt ${release.kind.id} source error: $error');
      return false;
    } on Object catch (error) {
      debugPrint('stream attempt ${release.kind.id} failed: ${error.runtimeType}');
      return false;
    }
  }
}

final playbackSessionProvider = NotifierProvider<PlaybackSessionNotifier, PlaybackSession?>(
  PlaybackSessionNotifier.new,
);

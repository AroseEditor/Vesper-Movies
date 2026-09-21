import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../design/widgets/poster_card.dart';
import '../../design/widgets/shimmer.dart';
import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../../storage/library_controller.dart';
import 'details_controller.dart';
import 'widgets/episode_tile.dart';
import 'widgets/release_sheet.dart';

class DetailsPage extends ConsumerStatefulWidget {
  const DetailsPage({super.key, required this.item});

  final CatalogItem item;

  @override
  ConsumerState<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends ConsumerState<DetailsPage> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final async = ref.watch(titleDetailsProvider(widget.item));
    final matches = ref.watch(sourceMatchesProvider(widget.item));

    return Scaffold(
      backgroundColor: VesperColors.canvas,
      body: async.when(
        loading: () => _DetailsSkeleton(item: widget.item, mode: mode),
        error: (error, stack) => _DetailsError(onBack: () => Navigator.of(context).maybePop()),
        data: (data) => _DetailsBody(
          data: data.withMatches(matches.value ?? const [], pending: matches.isLoading),
          mode: mode,
          season: _season,
          onSeasonChanged: (value) => setState(() => _season = value),
        ),
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({
    required this.data,
    required this.mode,
    required this.season,
    required this.onSeasonChanged,
  });

  final TitleDetails data;
  final InputMode mode;
  final int? season;
  final ValueChanged<int> onSeasonChanged;

  List<Season> _seasons(WidgetRef ref) {
    if (data.details.seasons.isNotEmpty) return data.details.seasons;
    final match = data.bestMatch;
    if (!data.details.isSeries || match == null) return const [];
    return ref.watch(matchSeasonsProvider(match)).value ?? const [];
  }

  bool _seasonsLoading(WidgetRef ref) {
    if (data.details.seasons.isNotEmpty || !data.details.isSeries) return false;
    final match = data.bestMatch;
    if (match == null) return data.matchesPending;
    return ref.watch(matchSeasonsProvider(match)).isLoading;
  }

  Season? _seasonFor(List<Season> seasons, int number) {
    if (seasons.isEmpty) return null;
    for (final entry in seasons) {
      if (entry.number == number) return entry;
    }
    return seasons.first;
  }

  Episode? _after(List<Season> seasons, int seasonNo, int episodeNo) {
    for (var i = 0; i < seasons.length; i++) {
      if (seasons[i].number != seasonNo) continue;
      final episodes = seasons[i].episodes;
      for (var j = 0; j < episodes.length; j++) {
        if (episodes[j].number != episodeNo) continue;
        if (j + 1 < episodes.length) return episodes[j + 1];
        if (i + 1 < seasons.length && seasons[i + 1].episodes.isNotEmpty) {
          return seasons[i + 1].episodes.first;
        }
        return null;
      }
    }
    return null;
  }

  Future<void> _play(
    BuildContext context,
    WidgetRef ref, {
    int seasonNo = 0,
    int episodeNo = 0,
  }) async {
    if (!data.isPlayable) return;

    await showReleaseSheet(
      context,
      ref: ref,
      matches: data.matches,
      item: data.item,
      title: data.details.title,
      season: seasonNo,
      episode: episodeNo,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = data.details;
    final seasons = _seasons(ref);
    final loadingEpisodes = _seasonsLoading(ref);
    final isSeries = details.isSeries && seasons.isNotEmpty;
    final library = ref.watch(libraryProvider).value;
    final id = data.item.id.value;

    final last = isSeries ? library?.lastEpisodeOf(id) : null;
    final active = _seasonFor(seasons, season ?? last?.season ?? 1);

    var playSeason = isSeries ? (active?.number ?? 1) : 0;
    var playEpisode = isSeries ? (active?.episodes.first.number ?? 1) : 0;
    var playLabel = 'Play';
    double? heroProgress;

    if (isSeries && last != null) {
      if (last.isInProgress) {
        playSeason = last.season;
        playEpisode = last.episode;
        playLabel = 'Resume S${last.season}E${last.episode}';
        heroProgress = last.progress;
      } else {
        final next = _after(seasons, last.season, last.episode);
        if (next != null) {
          playSeason = next.season;
          playEpisode = next.number;
          playLabel = 'Play S${next.season}E${next.number}';
        }
      }
    } else if (!isSeries) {
      final entry = library?.entryFor(id);
      if (entry != null && entry.isInProgress) {
        playLabel = 'Resume';
        heroProgress = entry.progress;
      }
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Backdrop(
            item: data.item,
            details: details,
            mode: mode,
            playable: data.isPlayable,
            matchLabel: data.isPlayable || data.matchesPending ? data.sourceLabel : null,
            playLabel: playLabel,
            progress: heroProgress,
            onPlay: () => _play(context, ref, seasonNo: playSeason, episodeNo: playEpisode),
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ),
        SliverToBoxAdapter(
          child: _Synopsis(details: details, mode: mode),
        ),
        if (isSeries) ...[
          SliverToBoxAdapter(
            child: _SeasonPicker(
              seasons: seasons,
              active: active?.number ?? 1,
              mode: mode,
              onChanged: onSeasonChanged,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 4, mode.gutter, mode.isTouch ? 110 : 40),
            sliver: SliverList.builder(
              itemCount: active?.episodes.length ?? 0,
              itemBuilder: (context, index) {
                final episode = active!.episodes[index];
                final watched = library?.entryFor(
                  id,
                  season: episode.season,
                  episode: episode.number,
                );
                return EpisodeTile(
                  episode: episode,
                  mode: mode,
                  enabled: data.isPlayable,
                  progress: watched == null ? null : (watched.completed ? 1.0 : watched.progress),
                  onPlay: () =>
                      _play(context, ref, seasonNo: episode.season, episodeNo: episode.number),
                );
              },
            ),
          ),
        ] else if (details.isSeries)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 24, mode.gutter, mode.isTouch ? 110 : 40),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: loadingEpisodes
                    ? const LoadingNote(label: 'Loading episodes', compact: true)
                    : const Text('No episode list found for this series', style: VesperType.meta),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.only(bottom: mode.isTouch ? 110 : 40),
            sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.item,
    required this.details,
    required this.mode,
    required this.playable,
    required this.matchLabel,
    required this.onPlay,
    required this.onBack,
    this.playLabel = 'Play',
    this.progress,
  });

  final CatalogItem item;
  final MediaDetails details;
  final InputMode mode;
  final bool playable;
  final String? matchLabel;
  final VoidCallback onPlay;
  final VoidCallback onBack;
  final String playLabel;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * (mode.isTouch ? 0.56 : 0.62)).clamp(300.0, size.height);
    final backdrop = details.backdropUrl ?? details.posterUrl;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null && backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (context, _) => const ColoredBox(color: VesperColors.surface),
              errorWidget: (context, _, error) => const ColoredBox(color: VesperColors.surface),
            )
          else
            const ColoredBox(color: VesperColors.surface),
          const DecoratedBox(decoration: BoxDecoration(gradient: VesperColors.heroFade)),
          const DecoratedBox(decoration: BoxDecoration(gradient: VesperColors.heroBottomFade)),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: mode.isTouch ? 6 : 14),
              child: Align(
                alignment: Alignment.topLeft,
                child: FocusableItem(
                  onActivate: onBack,
                  borderRadius: 22,
                  scaleOnFocus: false,
                  semanticLabel: 'Back',
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(VesperIcons.back, size: 26),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: mode.gutter,
            right: mode.gutter,
            bottom: 24,
            child: _TitleBlock(
              item: item,
              details: details,
              mode: mode,
              playable: playable,
              matchLabel: matchLabel,
              onPlay: onPlay,
              playLabel: playLabel,
              progress: progress,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.item,
    required this.details,
    required this.mode,
    required this.playable,
    required this.matchLabel,
    required this.onPlay,
    required this.playLabel,
    this.progress,
  });

  final CatalogItem item;
  final MediaDetails details;
  final InputMode mode;
  final bool playable;
  final String? matchLabel;
  final VoidCallback onPlay;
  final String playLabel;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final logo = details.logoUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo != null && logo.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mode.isTouch ? 96 : 132, maxWidth: 520),
            child: CachedNetworkImage(
              imageUrl: logo,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorWidget: (context, _, error) => Text(details.title, style: VesperType.heroTitle),
            ),
          )
        else
          Text(
            details.title,
            style: mode.isTouch ? VesperType.heroTitle : VesperType.display,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 12),
        _MetaRow(details: details),
        const SizedBox(height: 18),
        Row(
          children: [
            _PlayButton(enabled: playable, label: playLabel, onTap: onPlay),
            const SizedBox(width: 12),
            _ListButton(item: item),
            const SizedBox(width: 12),
            if (matchLabel != null)
              _SourceBadge(label: matchLabel!)
            else
              const _SourceBadge(label: 'No source found', muted: true),
          ],
        ),
        if (progress != null && progress! > 0) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: VesperColors.surfaceHover,
                valueColor: const AlwaysStoppedAnimation(VesperColors.accent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.details});

  final MediaDetails details;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];

    if (details.rating != null && details.rating!.isNotEmpty) {
      parts.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.star, size: 15, color: VesperColors.accent),
            const SizedBox(width: 3),
            Text(details.rating!, style: VesperType.meta),
          ],
        ),
      );
    }
    if (details.year != null && details.year!.isNotEmpty) {
      parts.add(Text(details.year!, style: VesperType.meta));
    }
    if (details.duration != null && details.duration!.isNotEmpty) {
      parts.add(Text(details.duration!, style: VesperType.meta));
    }
    parts.add(Text(details.isSeries ? 'Series' : 'Film', style: VesperType.meta));
    for (final genre in details.genres.take(3)) {
      parts.add(Text(genre, style: VesperType.meta));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            const Text('|', style: TextStyle(color: VesperColors.textTertiary, fontSize: 11)),
          parts[i],
        ],
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.enabled, required this.label, required this.onTap});

  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: enabled ? onTap : null,
      autofocus: enabled,
      borderRadius: 6,
      scaleOnFocus: false,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: VesperMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
        decoration: BoxDecoration(
          color: enabled ? VesperColors.accent : VesperColors.surfaceHover,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              VesperIcons.play,
              size: 24,
              color: enabled ? VesperColors.canvas : VesperColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: VesperType.button.copyWith(
                color: enabled ? VesperColors.canvas : VesperColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: VesperColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            muted ? VesperIcons.warning : VesperIcons.source,
            size: 15,
            color: muted ? VesperColors.textTertiary : VesperColors.accent,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: VesperType.label.copyWith(
              color: muted ? VesperColors.textTertiary : VesperColors.textHover,
            ),
          ),
        ],
      ),
    );
  }
}

class _Synopsis extends StatelessWidget {
  const _Synopsis({required this.details, required this.mode});

  final MediaDetails details;
  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    final description = details.description;
    if ((description == null || description.isEmpty) && details.cast == null) {
      return const SizedBox(height: 12);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(mode.gutter, 20, mode.gutter, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null && description.isNotEmpty)
              Text(description, style: VesperType.body.copyWith(color: VesperColors.textHover)),
            if (details.cast != null) ...[
              const SizedBox(height: 12),
              _CreditLine(label: 'Cast', value: details.cast!),
            ],
            if (details.director != null) ...[
              const SizedBox(height: 4),
              _CreditLine(label: 'Director', value: details.director!),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreditLine extends StatelessWidget {
  const _CreditLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: VesperType.meta,
        children: [
          TextSpan(text: '$label: ', style: VesperType.meta),
          TextSpan(
            text: value,
            style: VesperType.meta.copyWith(color: VesperColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.seasons,
    required this.active,
    required this.mode,
    required this.onChanged,
  });

  final List<Season> seasons;
  final int active;
  final InputMode mode;
  final ValueChanged<int> onChanged;

  static String _count(int episodes) => episodes == 1 ? '1 episode' : '$episodes episodes';

  @override
  Widget build(BuildContext context) {
    Season? current;
    for (final season in seasons) {
      if (season.number == active) current = season;
    }
    current ??= seasons.isEmpty ? null : seasons.first;

    return Padding(
      padding: EdgeInsets.fromLTRB(mode.gutter, 18, mode.gutter, 10),
      child: Row(
        children: [
          const Text('Episodes', style: VesperType.sectionTitle),
          const Spacer(),
          if (seasons.length > 1)
            MenuAnchor(
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(VesperColors.surfaceRaised),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                maximumSize: const WidgetStatePropertyAll(Size(280, 420)),
              ),
              alignmentOffset: const Offset(0, 6),
              menuChildren: [
                for (final season in seasons)
                  MenuItemButton(
                    onPressed: () => onChanged(season.number),
                    leadingIcon: SizedBox(
                      width: 20,
                      child: season.number == current?.number
                          ? const Icon(VesperIcons.check, size: 18, color: VesperColors.accent)
                          : null,
                    ),
                    trailingIcon: Text(_count(season.episodes.length), style: VesperType.meta),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        'Season ${season.number}',
                        style: VesperType.label.copyWith(
                          color: season.number == current?.number
                              ? VesperColors.textPrimary
                              : VesperColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
              builder: (context, controller, child) => FocusableItem(
                onActivate: () => controller.isOpen ? controller.close() : controller.open(),
                borderRadius: 6,
                scaleOnFocus: false,
                semanticLabel: 'Choose season',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: VesperColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: VesperColors.surfaceHover),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Season ${current?.number ?? 1}', style: VesperType.label),
                      const SizedBox(width: 6),
                      const Icon(VesperIcons.expand, size: 20),
                    ],
                  ),
                ),
              ),
            )
          else if (current != null)
            Text(_count(current.episodes.length), style: VesperType.meta),
        ],
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton({required this.item, required this.mode});

  final CatalogItem item;
  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: (size.height * 0.6).clamp(300.0, size.height),
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterArt(item: item, useBackdrop: true, compactFallback: true),
                const DecoratedBox(decoration: BoxDecoration(gradient: VesperColors.heroFade)),
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: VesperColors.heroBottomFade),
                ),
                Positioned(
                  left: mode.gutter,
                  bottom: 30,
                  child: Text(
                    item.title,
                    style: mode.isTouch ? VesperType.heroTitle : VesperType.display,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: mode.rowGap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: mode.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Shimmer(width: size.width * 0.5, height: 14, borderRadius: 4),
                const SizedBox(height: 10),
                Shimmer(width: size.width * 0.42, height: 14, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsError extends StatelessWidget {
  const _DetailsError({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.warning, size: 42, color: VesperColors.textTertiary),
            const SizedBox(height: 14),
            const Text('Could not load this title', style: VesperType.sectionTitle),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              style: VesperType.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FocusableItem(
              onActivate: onBack,
              autofocus: true,
              borderRadius: 6,
              scaleOnFocus: false,
              semanticLabel: 'Go back',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: VesperColors.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('Go back', style: VesperType.button),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListButton extends ConsumerWidget {
  const _ListButton({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(libraryProvider).value?.isFavourite(item.id.value) ?? false;

    return FocusableItem(
      onActivate: () => ref.read(libraryProvider.notifier).toggleFavourite(item),
      borderRadius: 6,
      scaleOnFocus: false,
      semanticLabel: saved ? 'Remove from My List' : 'Add to My List',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: VesperColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              saved ? VesperIcons.check : VesperIcons.add,
              size: 21,
              color: saved ? VesperColors.accent : VesperColors.textPrimary,
            ),
            const SizedBox(width: 7),
            Text(
              saved ? 'In List' : 'My List',
              style: VesperType.button.copyWith(color: VesperColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

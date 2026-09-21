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
  int _season = 1;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final async = ref.watch(titleDetailsProvider(widget.item));

    return Scaffold(
      backgroundColor: VesperColors.canvas,
      body: async.when(
        loading: () => _DetailsSkeleton(item: widget.item, mode: mode),
        error: (error, stack) => _DetailsError(onBack: () => Navigator.of(context).maybePop()),
        data: (data) => _DetailsBody(
          data: data,
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
  final int season;
  final ValueChanged<int> onSeasonChanged;

  Season? get _activeSeason {
    final seasons = data.details.seasons;
    if (seasons.isEmpty) return null;
    for (final entry in seasons) {
      if (entry.number == season) return entry;
    }
    return seasons.first;
  }

  Future<void> _play(
    BuildContext context,
    WidgetRef ref, {
    int seasonNo = 0,
    int episodeNo = 0,
  }) async {
    final match = data.bestMatch;
    if (match == null) return;

    await showReleaseSheet(
      context,
      ref: ref,
      match: match,
      title: data.details.title,
      season: seasonNo,
      episode: episodeNo,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = data.details;
    final active = _activeSeason;
    final isSeries = details.isSeries && details.seasons.isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Backdrop(
            details: details,
            mode: mode,
            playable: data.isPlayable,
            matchLabel: data.bestMatch?.kind.label,
            onPlay: () => _play(
              context,
              ref,
              seasonNo: isSeries ? (active?.number ?? 1) : 0,
              episodeNo: isSeries ? (active?.episodes.first.number ?? 1) : 0,
            ),
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ),
        SliverToBoxAdapter(
          child: _Synopsis(details: details, mode: mode),
        ),
        if (isSeries) ...[
          SliverToBoxAdapter(
            child: _SeasonPicker(
              seasons: details.seasons,
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
                return EpisodeTile(
                  episode: episode,
                  mode: mode,
                  enabled: data.isPlayable,
                  onPlay: () =>
                      _play(context, ref, seasonNo: episode.season, episodeNo: episode.number),
                );
              },
            ),
          ),
        ] else
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
    required this.details,
    required this.mode,
    required this.playable,
    required this.matchLabel,
    required this.onPlay,
    required this.onBack,
  });

  final MediaDetails details;
  final InputMode mode;
  final bool playable;
  final String? matchLabel;
  final VoidCallback onPlay;
  final VoidCallback onBack;

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
              details: details,
              mode: mode,
              playable: playable,
              matchLabel: matchLabel,
              onPlay: onPlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.details,
    required this.mode,
    required this.playable,
    required this.matchLabel,
    required this.onPlay,
  });

  final MediaDetails details;
  final InputMode mode;
  final bool playable;
  final String? matchLabel;
  final VoidCallback onPlay;

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
            _PlayButton(enabled: playable, onTap: onPlay),
            const SizedBox(width: 12),
            if (matchLabel != null)
              _SourceBadge(label: matchLabel!)
            else
              const _SourceBadge(label: 'No source found', muted: true),
          ],
        ),
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
  const _PlayButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: enabled ? onTap : null,
      autofocus: enabled,
      borderRadius: 6,
      scaleOnFocus: false,
      semanticLabel: 'Play',
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
              'Play',
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

  @override
  Widget build(BuildContext context) {
    if (seasons.length <= 1) {
      return Padding(
        padding: EdgeInsets.fromLTRB(mode.gutter, 18, mode.gutter, 8),
        child: const Text('Episodes', style: VesperType.sectionTitle),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(mode.gutter, 18, mode.gutter, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Episodes', style: VesperType.sectionTitle),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final season = seasons[index];
                final selected = season.number == active;

                return FocusableItem(
                  onActivate: () => onChanged(season.number),
                  borderRadius: 16,
                  scaleOnFocus: false,
                  semanticLabel: 'Season ${season.number}',
                  child: AnimatedContainer(
                    duration: VesperMotion.fast,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? VesperColors.accent : VesperColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Season ${season.number}',
                      style: VesperType.label.copyWith(
                        color: selected ? VesperColors.canvas : VesperColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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

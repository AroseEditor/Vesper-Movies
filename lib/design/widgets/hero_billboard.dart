import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media.dart';
import '../../shell/input_mode.dart';
import '../colors.dart';
import '../icons.dart';
import '../motion.dart';
import '../typography.dart';
import 'focusable_item.dart';
import 'poster_card.dart';

class HeroBillboard extends StatelessWidget {
  const HeroBillboard({
    super.key,
    required this.item,
    required this.mode,
    this.description,
    this.onPlay,
    this.onInfo,
    this.onToggleList,
    this.inList = false,
    this.autofocusPlay = false,
  });

  final CatalogItem item;
  final InputMode mode;
  final String? description;
  final VoidCallback? onPlay;
  final VoidCallback? onInfo;
  final VoidCallback? onToggleList;
  final bool inList;
  final bool autofocusPlay;

  double _height(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final preferred = switch (mode) {
      InputMode.touch => size.height * 0.62,
      InputMode.desktop => size.height * 0.68,
      InputMode.tv => size.height * 0.72,
    };
    final peek = mode.posterWidth * 0.62 + mode.rowGap;
    return preferred.clamp(
      size.height * 0.34,
      (size.height - peek).clamp(220.0, size.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = _height(context);
    final backdrop = item.backdropUrl ?? item.posterUrl;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop != null && backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fadeInDuration: const Duration(milliseconds: 320),
              placeholder: (context, _) =>
                  const ColoredBox(color: VesperColors.surface),
              errorWidget: (context, _, error) =>
                  PosterFallback(item: item, compact: true),
            )
          else
            PosterFallback(item: item, compact: true),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: VesperColors.heroFade),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: VesperColors.heroBottomFade),
          ),
          Positioned(
            left: mode.gutter,
            right: mode.gutter,
            bottom: mode.isTouch ? 26 : 52,
            child: _HeroContent(
              item: item,
              mode: mode,
              description: description,
              onPlay: onPlay,
              onInfo: onInfo,
              onToggleList: onToggleList,
              inList: inList,
              autofocusPlay: autofocusPlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.item,
    required this.mode,
    required this.description,
    required this.onPlay,
    required this.onInfo,
    required this.onToggleList,
    required this.inList,
    required this.autofocusPlay,
  });

  final CatalogItem item;
  final InputMode mode;
  final String? description;
  final VoidCallback? onPlay;
  final VoidCallback? onInfo;
  final VoidCallback? onToggleList;
  final bool inList;
  final bool autofocusPlay;

  @override
  Widget build(BuildContext context) {
    final maxWidth = mode.isTouch ? double.infinity : 560.0;
    final logo = item.logoUrl;

    return Align(
      alignment: mode.isTouch ? Alignment.center : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: mode.isTouch
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo != null && logo.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: mode.isTouch ? 110 : 150,
                ),
                child: CachedNetworkImage(
                  imageUrl: logo,
                  fit: BoxFit.contain,
                  alignment: mode.isTouch
                      ? Alignment.center
                      : Alignment.centerLeft,
                  errorWidget: (context, _, error) =>
                      _TitleText(item: item, mode: mode),
                ),
              )
            else
              _TitleText(item: item, mode: mode),
            const SizedBox(height: 14),
            _MetaLine(item: item, mode: mode),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description!,
                style: VesperType.body.copyWith(color: VesperColors.textHover),
                maxLines: mode.isTouch ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                textAlign: mode.isTouch ? TextAlign.center : TextAlign.start,
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HeroButton(
                  label: 'Play',
                  icon: VesperIcons.play,
                  filled: true,
                  autofocus: autofocusPlay,
                  onTap: onPlay,
                ),
                const SizedBox(width: 12),
                HeroButton(
                  label: 'More Info',
                  icon: VesperIcons.info,
                  onTap: onInfo,
                ),
                if (onToggleList != null) ...[
                  const SizedBox(width: 12),
                  HeroButton(
                    label: inList ? 'In List' : 'My List',
                    icon: inList ? VesperIcons.check : VesperIcons.add,
                    onTap: onToggleList,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleText extends StatelessWidget {
  const _TitleText({required this.item, required this.mode});

  final CatalogItem item;
  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    return Text(
      item.title,
      style: mode.isTouch ? VesperType.heroTitle : VesperType.display,
      textAlign: mode.isTouch ? TextAlign.center : TextAlign.start,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.item, required this.mode});

  final CatalogItem item;
  final InputMode mode;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];

    if (item.rating != null) {
      parts.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(VesperIcons.star, size: 15, color: VesperColors.accent),
            const SizedBox(width: 3),
            Text(
              item.rating!.toStringAsFixed(1),
              style: VesperType.meta.copyWith(
                color: VesperColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    if (item.year != null) {
      parts.add(Text(item.year!, style: VesperType.meta));
    }
    parts.add(Text(item.isSeries ? 'Series' : 'Film', style: VesperType.meta));
    if (item.seasonCount != null && item.seasonCount! > 0) {
      final count = item.seasonCount!;
      parts.add(
        Text(
          '$count ${count == 1 ? 'Season' : 'Seasons'}',
          style: VesperType.meta,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: mode.isTouch ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            const Text(
              '|',
              style: TextStyle(color: VesperColors.textTertiary, fontSize: 11),
            ),
          parts[i],
        ],
      ],
    );
  }
}

class HeroButton extends StatelessWidget {
  const HeroButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.filled = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      autofocus: autofocus,
      borderRadius: 6,
      scaleOnFocus: false,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: VesperMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          color: filled
              ? VesperColors.accent
              : VesperColors.surfaceRaised.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: filled ? VesperColors.canvas : VesperColors.textPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: VesperType.button.copyWith(
                color: filled ? VesperColors.canvas : VesperColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

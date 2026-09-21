import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media.dart';
import '../colors.dart';
import '../motion.dart';
import '../typography.dart';
import 'focusable_item.dart';

String upgradePosterUrl(String url) {
  if (!url.contains('images.metahub.space')) return url;
  return url.replaceFirst('/small/', '/medium/');
}

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    this.onTap,
    this.onFocusChange,
    this.autofocus = false,
    this.progress,
    this.aspectRatio = 2 / 3,
    this.showLabel = true,
  });

  final CatalogItem item;
  final double width;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final double? progress;
  final double aspectRatio;
  final bool showLabel;

  static double labelHeight(bool showLabel) => showLabel ? 44 : 0;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  void _handleFocus(bool value) {
    if (_focused != value) setState(() => _focused = value);
    widget.onFocusChange?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusableItem(
            onActivate: widget.onTap,
            onFocusChange: _handleFocus,
            autofocus: widget.autofocus,
            semanticLabel: widget.item.title,
            child: AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterArt(
                    item: widget.item,
                    compactFallback: widget.showLabel,
                  ),
                  if (widget.progress != null && widget.progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: PosterProgressBar(value: widget.progress!),
                    ),
                ],
              ),
            ),
          ),
          if (widget.showLabel) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: PosterCard.labelHeight(true) - 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: VesperMotion.fast,
                    style: VesperType.cardTitle.copyWith(
                      fontSize: 13.5,
                      color: _focused
                          ? VesperColors.accent
                          : VesperColors.textHover,
                    ),
                    child: Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metaLine(widget.item),
                    style: VesperType.meta.copyWith(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _metaLine(CatalogItem item) {
    final parts = <String>[];
    if (item.year != null && item.year!.isNotEmpty) parts.add(item.year!);
    parts.add(item.isSeries ? 'Series' : 'Film');
    if (item.rating != null) parts.add(item.rating!.toStringAsFixed(1));
    return parts.join('  ');
  }
}

class PosterArt extends StatelessWidget {
  const PosterArt({
    super.key,
    required this.item,
    this.useBackdrop = false,
    this.compactFallback = false,
  });

  final CatalogItem item;
  final bool useBackdrop;
  final bool compactFallback;

  @override
  Widget build(BuildContext context) {
    final raw = useBackdrop
        ? (item.backdropUrl ?? item.posterUrl)
        : item.posterUrl;
    if (raw == null || raw.isEmpty) {
      return PosterFallback(item: item, compact: compactFallback);
    }

    return CachedNetworkImage(
      imageUrl: upgradePosterUrl(raw),
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (context, _) =>
          const ColoredBox(color: VesperColors.surface),
      errorWidget: (context, _, error) =>
          PosterFallback(item: item, compact: compactFallback),
    );
  }
}

class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key, required this.item, this.compact = false});

  final CatalogItem item;
  final bool compact;

  static const palettes = <List<Color>>[
    [Color(0xFF15343A), Color(0xFF0C1C20)],
    [Color(0xFF241F42), Color(0xFF12101F)],
    [Color(0xFF123027), Color(0xFF0A1A15)],
    [Color(0xFF2A1F2D), Color(0xFF150F17)],
    [Color(0xFF102A3A), Color(0xFF09161F)],
    [Color(0xFF1E2B1A), Color(0xFF10170E)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = palettes[item.title.hashCode.abs() % palettes.length];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: compact
          ? const SizedBox.expand()
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    item.title,
                    style: VesperType.cardTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.year != null) ...[
                    const SizedBox(height: 4),
                    Text(item.year!, style: VesperType.meta),
                  ],
                ],
              ),
            ),
    );
  }
}

class PosterProgressBar extends StatelessWidget {
  const PosterProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      color: VesperColors.surfaceHover,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: const ColoredBox(color: VesperColors.accent),
      ),
    );
  }
}

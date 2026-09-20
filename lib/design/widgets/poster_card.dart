import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media.dart';
import '../colors.dart';
import '../typography.dart';
import 'focusable_item.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    this.onTap,
    this.onFocusChange,
    this.autofocus = false,
    this.progress,
    this.aspectRatio = 2 / 3,
  });

  final CatalogItem item;
  final double width;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final double? progress;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FocusableItem(
        onActivate: onTap,
        onFocusChange: onFocusChange,
        autofocus: autofocus,
        semanticLabel: item.title,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterArt(item: item),
              if (progress != null && progress! > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PosterProgressBar(value: progress!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosterArt extends StatelessWidget {
  const PosterArt({super.key, required this.item, this.useBackdrop = false});

  final CatalogItem item;
  final bool useBackdrop;

  @override
  Widget build(BuildContext context) {
    final url = useBackdrop ? (item.backdropUrl ?? item.posterUrl) : item.posterUrl;
    if (url == null || url.isEmpty) {
      return PosterFallback(item: item);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (context, _) => const ColoredBox(color: VesperColors.surface),
      errorWidget: (context, _, error) => PosterFallback(item: item),
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

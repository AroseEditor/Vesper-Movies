import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../design/colors.dart';
import '../../../design/icons.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/focusable_item.dart';
import '../../../models/media.dart';
import '../../../shell/input_mode.dart';

class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    required this.mode,
    required this.onPlay,
    this.enabled = true,
    this.progress,
  });

  final Episode episode;
  final InputMode mode;
  final VoidCallback onPlay;
  final bool enabled;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final thumbWidth = mode.isTouch ? 132.0 : 176.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FocusableItem(
        onActivate: enabled ? onPlay : null,
        borderRadius: 8,
        scaleOnFocus: false,
        semanticLabel: '${episode.label} ${episode.title ?? ''}',
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${episode.number}',
                  style: VesperType.sectionTitle.copyWith(
                    color: VesperColors.textTertiary,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: thumbWidth,
                  height: thumbWidth * 9 / 16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (episode.stillUrl != null && episode.stillUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: episode.stillUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, _) =>
                              const ColoredBox(color: VesperColors.surface),
                          errorWidget: (context, _, error) =>
                              const ColoredBox(color: VesperColors.surface),
                        )
                      else
                        const ColoredBox(color: VesperColors.surface),
                      Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(VesperIcons.play, size: 22),
                        ),
                      ),
                      if (progress != null && progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 3,
                            color: VesperColors.surfaceHover,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress!.clamp(0.0, 1.0),
                              child: const ColoredBox(color: VesperColors.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      episode.title ?? episode.label,
                      style: VesperType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (episode.overview != null && episode.overview!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        episode.overview!,
                        style: VesperType.meta,
                        maxLines: mode.isTouch ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

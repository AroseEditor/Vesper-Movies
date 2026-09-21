import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../design/colors.dart';
import '../../../design/icons.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/focusable_item.dart';
import '../../../models/media.dart';
import '../../../models/release.dart';
import '../../../player/player_controller.dart';
import '../../../sources/registry.dart';
import '../../../sources/source_matcher.dart';
import '../../../storage/library_controller.dart';
import '../../player/player_page.dart';
import '../details_controller.dart';

Future<void> showReleaseSheet(
  BuildContext context, {
  required WidgetRef ref,
  required SourceMatch match,
  required CatalogItem item,
  required String title,
  int season = 0,
  int episode = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: VesperColors.canvasDeep,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) =>
        ReleaseSheet(match: match, item: item, title: title, season: season, episode: episode),
  );
}

class ReleaseSheet extends ConsumerWidget {
  const ReleaseSheet({
    super.key,
    required this.match,
    required this.item,
    required this.title,
    this.season = 0,
    this.episode = 0,
  });

  final SourceMatch match;
  final CatalogItem item;
  final String title;
  final int season;
  final int episode;

  String get _subtitle => season > 0 ? 'S${season}E$episode' : '';

  Future<void> _launch(BuildContext context, WidgetRef ref, Release release) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();

    try {
      final target = await resolvePlayback(
        ref.read(sourceRegistryProvider),
        PlaybackRequest(
          release: release,
          match: match,
          title: title,
          subtitle: _subtitle.isEmpty ? null : _subtitle,
          season: season,
          episode: episode,
        ),
      );

      final saved = ref
          .read(libraryProvider)
          .value
          ?.entryFor(item.id.value, season: season, episode: episode);
      final resumeFrom = saved != null && saved.isInProgress ? saved.resumeAt : Duration.zero;

      final controller = ref.read(playerControllerProvider.notifier);
      await controller.load(
        PlaybackTarget(
          source: target.source,
          title: target.title,
          subtitle: target.subtitle,
          startAt: resumeFrom,
          season: target.season,
          episode: target.episode,
          mediaId: target.mediaId,
        ),
      );

      await navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => PlayerPage(
            onProgress: (position, duration, completed) {
              unawaited(
                ref
                    .read(libraryProvider.notifier)
                    .recordProgress(
                      item: item,
                      position: position,
                      duration: duration,
                      season: season,
                      episode: episode,
                      completed: completed,
                    ),
              );
            },
          ),
        ),
      );
      await controller.stop();
    } on SourceError catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.userMessage(match.kind)),
          backgroundColor: VesperColors.surfaceRaised,
        ),
      );
    } on Object catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That stream would not start.'),
          backgroundColor: VesperColors.surfaceRaised,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = EpisodeRef(match, season: season, episode: episode);
    final releases = ref.watch(releasesProvider(target));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Streams', style: VesperType.sectionTitle),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle.isEmpty ? '$title  ${match.kind.label}' : '$title  $_subtitle',
                    style: VesperType.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Flexible(
              child: releases.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 44),
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(color: VesperColors.accent, strokeWidth: 3),
                    ),
                  ),
                ),
                error: (error, stack) => _SheetMessage(
                  message: error is SourceError
                      ? error.userMessage(match.kind)
                      : 'No streams were returned.',
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const _SheetMessage(message: 'No streams available for this episode.');
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final release = items[index];
                      return _ReleaseRow(
                        release: release,
                        autofocus: index == 0,
                        onTap: () => _launch(context, ref, release),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({required this.release, required this.onTap, this.autofocus = false});

  final Release release;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (release.quality != null) release.quality!,
      if (release.codec != null) release.codec!,
      if (release.language != null) release.language!,
      if (release.sizeLabel.isNotEmpty) release.sizeLabel,
    ];

    return FocusableItem(
      onActivate: onTap,
      autofocus: autofocus,
      borderRadius: 8,
      scaleOnFocus: false,
      semanticLabel: release.filename,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            const Icon(VesperIcons.play, size: 24, color: VesperColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    release.sourceLabel,
                    style: VesperType.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta.join('  '),
                      style: VesperType.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(VesperIcons.chevronRight, size: 20, color: VesperColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Row(
        children: [
          const Icon(VesperIcons.warning, size: 20, color: VesperColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: VesperType.body)),
        ],
      ),
    );
  }
}

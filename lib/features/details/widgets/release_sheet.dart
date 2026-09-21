import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/colors.dart';
import '../../../design/icons.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/focusable_item.dart';
import '../../../downloads/download_queue.dart';
import '../../../models/media.dart';
import '../../../models/release.dart';
import '../../../sources/source_matcher.dart';
import '../details_controller.dart';
import '../launch_playback.dart';

Future<void> showReleaseSheet(
  BuildContext context, {
  required WidgetRef ref,
  required List<SourceMatch> matches,
  required CatalogItem item,
  required String title,
  List<Season> seasons = const [],
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
    builder: (sheetContext) => ReleaseSheet(
      matches: matches,
      item: item,
      title: title,
      seasons: seasons,
      season: season,
      episode: episode,
    ),
  );
}

class ReleaseSheet extends ConsumerWidget {
  const ReleaseSheet({
    super.key,
    required this.matches,
    required this.item,
    required this.title,
    this.seasons = const [],
    this.season = 0,
    this.episode = 0,
  });

  final List<SourceMatch> matches;
  final CatalogItem item;
  final String title;
  final List<Season> seasons;
  final int season;
  final int episode;

  String get _subtitle => season > 0 ? 'S${season}E$episode' : '';

  Future<void> _launch(BuildContext context, Release release) async {
    final root = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    await launchPlayback(
      root,
      item: item,
      title: title,
      matches: matches,
      seasons: seasons,
      season: season,
      episode: episode,
      preferred: release,
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref, Release release) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    final mirror = release.mirrors.first;
    final error = await ref
        .read(downloadQueueProvider.notifier)
        .enqueue(
          item: item,
          release: release,
          headers: mirror.headers,
          url: mirror.url,
          season: season,
          episode: episode,
        );

    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Added to downloads.'),
        backgroundColor: VesperColors.surfaceRaised,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = EpisodeRef(matches, item, season: season, episode: episode);
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
                    _subtitle.isEmpty ? title : '$title  $_subtitle',
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
                error: (error, stack) =>
                    const _SheetMessage(message: 'No streams were returned for this title.'),
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
                        onTap: () => _launch(context, release),
                        onDownload: () => _download(context, ref, release),
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
  const _ReleaseRow({
    required this.release,
    required this.onTap,
    required this.onDownload,
    this.autofocus = false,
  });

  final Release release;
  final VoidCallback onTap;
  final VoidCallback onDownload;
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
            FocusableItem(
              onActivate: onDownload,
              borderRadius: 16,
              scaleOnFocus: false,
              semanticLabel: 'Download this stream',
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(VesperIcons.downloads, size: 21, color: VesperColors.textSecondary),
              ),
            ),
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

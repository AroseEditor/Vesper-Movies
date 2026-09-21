import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../downloads/download_engine.dart';
import '../../downloads/download_queue.dart';
import '../../models/provider_kind.dart';
import '../../models/release.dart';
import '../../player/player_controller.dart';
import '../../shell/input_mode.dart';
import '../player/player_page.dart';
import '../settings/settings_page.dart';

class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  Future<void> _playLocal(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
  ) async {
    final navigator = Navigator.of(context);
    final controller = ref.read(playerControllerProvider.notifier);

    await controller.load(
      PlaybackTarget(
        source: PlaybackSource(
          kind: ProviderKind.moviebox,
          url: Uri.file(task.filePath).toString(),
          sourceLabel: 'Downloaded',
        ),
        title: task.title,
        subtitle: task.subtitle,
      ),
    );
    await navigator.push(
      MaterialPageRoute<void>(builder: (context) => const PlayerPage()),
    );
    await controller.stop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    final tasks =
        ref.watch(downloadQueueProvider).value ?? const <DownloadTask>[];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(mode.gutter, 16, mode.gutter, 12),
            child: Row(
              children: [
                const Text('Downloads', style: VesperType.sectionTitle),
                const Spacer(),
                FocusableItem(
                  onActivate: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const SettingsPage(),
                    ),
                  ),
                  borderRadius: 18,
                  scaleOnFocus: false,
                  semanticLabel: 'Settings',
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(VesperIcons.settings, size: 22),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? const _DownloadsEmpty()
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      mode.gutter,
                      0,
                      mode.gutter,
                      mode.isTouch ? 110 : 30,
                    ),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _DownloadRow(
                        task: task,
                        autofocus: mode.isTv && index == 0,
                        onPlay: () => _playLocal(context, ref, task),
                        onPause: () => ref
                            .read(downloadQueueProvider.notifier)
                            .pause(task.id),
                        onResume: () => ref
                            .read(downloadQueueProvider.notifier)
                            .start(task.id),
                        onRemove: () => ref
                            .read(downloadQueueProvider.notifier)
                            .remove(task.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.task,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    this.autofocus = false,
  });

  final DownloadTask task;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final bool autofocus;

  String get _status => switch (task.status) {
    DownloadStatus.queued => 'Queued',
    DownloadStatus.running =>
      '${formatBytes(task.received)} of ${formatBytes(task.total)}  ${formatSpeed(task.speed)}',
    DownloadStatus.paused => 'Paused at ${formatBytes(task.received)}',
    DownloadStatus.completed => 'Saved  ${formatBytes(task.received)}',
    DownloadStatus.failed => task.error ?? 'Failed',
  };

  bool get _exists => File(task.filePath).existsSync();

  @override
  Widget build(BuildContext context) {
    final done = task.status == DownloadStatus.completed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FocusableItem(
        onActivate: done && _exists
            ? onPlay
            : (task.isActive ? onPause : onResume),
        autofocus: autofocus,
        borderRadius: 8,
        scaleOnFocus: false,
        semanticLabel: task.title,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: 62,
                  height: 93,
                  child: task.posterUrl == null
                      ? const ColoredBox(color: VesperColors.surface)
                      : CachedNetworkImage(
                          imageUrl: task.posterUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, _) =>
                              const ColoredBox(color: VesperColors.surface),
                          errorWidget: (context, _, error) =>
                              const ColoredBox(color: VesperColors.surface),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      task.title,
                      style: VesperType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _status,
                      style: VesperType.meta.copyWith(
                        color: task.status == DownloadStatus.failed
                            ? VesperColors.danger
                            : VesperColors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!done) ...[
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: AnimatedContainer(
                          duration: VesperMotion.fast,
                          height: 4,
                          color: VesperColors.surfaceHover,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: task.fraction,
                            child: const ColoredBox(color: VesperColors.accent),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (done)
                    _RowAction(
                      icon: VesperIcons.play,
                      label: 'Play',
                      onTap: onPlay,
                    )
                  else if (task.isActive)
                    _RowAction(
                      icon: VesperIcons.pauseCircle,
                      label: 'Pause',
                      onTap: onPause,
                    )
                  else
                    _RowAction(
                      icon: VesperIcons.play,
                      label: 'Resume',
                      onTap: onResume,
                    ),
                  _RowAction(
                    icon: VesperIcons.deleteItem,
                    label: 'Remove',
                    onTap: onRemove,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      borderRadius: 16,
      scaleOnFocus: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 21, color: VesperColors.textSecondary),
      ),
    );
  }
}

class _DownloadsEmpty extends StatelessWidget {
  const _DownloadsEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              VesperIcons.downloads,
              size: 42,
              color: VesperColors.textTertiary,
            ),
            SizedBox(height: 14),
            Text('Nothing downloaded yet', style: VesperType.sectionTitle),
            SizedBox(height: 7),
            Text(
              'Open any title, choose a stream and pick Download to save it for offline viewing.',
              style: VesperType.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

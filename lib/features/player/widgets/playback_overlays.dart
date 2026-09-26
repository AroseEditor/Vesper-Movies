import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/colors.dart';
import '../../../design/icons.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/choice_dialog.dart';
import '../../../design/widgets/focusable_item.dart';
import '../../../models/release.dart';
import '../../../player/player_controller.dart';
import '../../details/playback_session.dart';

const _nextLead = Duration(seconds: 20);
const _fallbackIntroStart = Duration(seconds: 15);
const _fallbackIntroEnd = Duration(minutes: 4);
const _fallbackIntroSkip = Duration(seconds: 85);

final _introPattern = RegExp(r'\b(intro|opening|op|theme)\b', caseSensitive: false);
final _recapPattern = RegExp(r'\b(recap|previously|summary)\b', caseSensitive: false);
final _creditsPattern = RegExp(r'\b(credits|ending|outro|ed|end)\b', caseSensitive: false);

String releaseMeta(Release release) {
  return [
    if (release.quality != null) release.quality!,
    if (release.codec != null) release.codec!,
    if (release.language != null) release.language!,
    if (release.rip != null) release.rip!,
    if (release.sizeLabel.isNotEmpty) release.sizeLabel,
  ].join('  ');
}

Future<void> showSourceDialog(BuildContext context, WidgetRef ref) async {
  final session = ref.read(playbackSessionProvider);
  if (session == null) return;
  final releases = session.releases;
  final chosen = await showChoiceDialog<Release>(
    context,
    title: releases.isEmpty ? 'Finding sources' : '${releases.length} sources',
    options: [
      for (final release in releases)
        ChoiceOption(
          value: release,
          label: '${release.kind.label}  ${release.filename}',
          subtitle: releaseMeta(release),
          selected: release == session.current,
        ),
    ],
  );
  if (chosen != null) unawaited(ref.read(playbackSessionProvider.notifier).switchTo(chosen));
}

class CloudSourceButton extends ConsumerWidget {
  const CloudSourceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(playbackSessionProvider);
    if (session == null) return const SizedBox.shrink();

    return FocusableItem(
      onActivate: () => unawaited(showSourceDialog(context, ref)),
      borderRadius: 22,
      scaleOnFocus: false,
      semanticLabel: 'Change source',
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: session.switching
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: VesperColors.accent),
              )
            : const Icon(VesperIcons.cloud, size: 26),
      ),
    );
  }
}

class _Segment {
  const _Segment(this.start, this.end, this.label);

  final Duration start;
  final Duration end;
  final String label;
}

class PlaybackOverlays extends ConsumerStatefulWidget {
  const PlaybackOverlays({super.key, required this.onInteract});

  final VoidCallback onInteract;

  @override
  ConsumerState<PlaybackOverlays> createState() => _PlaybackOverlaysState();
}

class _PlaybackOverlaysState extends ConsumerState<PlaybackOverlays> {
  String? _loadedFor;
  List<_Segment> _skips = const [];
  Duration? _creditsAt;
  final Set<String> _dismissed = {};
  bool _advancing = false;

  Future<void> _loadChapters(String key) async {
    _loadedFor = key;
    _skips = const [];
    _creditsAt = null;

    final chapters = await ref.read(playerControllerProvider.notifier).chapters();
    if (!mounted || _loadedFor != key) return;

    final skips = <_Segment>[];
    Duration? credits;
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final end = i + 1 < chapters.length ? chapters[i + 1].start : null;
      if (_recapPattern.hasMatch(chapter.title) && end != null) {
        skips.add(_Segment(chapter.start, end, 'Skip Recap'));
      } else if (_introPattern.hasMatch(chapter.title) && end != null) {
        skips.add(_Segment(chapter.start, end, 'Skip Intro'));
      } else if (_creditsPattern.hasMatch(chapter.title) && i > 0) {
        credits ??= chapter.start;
      }
    }
    setState(() {
      _skips = skips;
      _creditsAt = credits;
    });
  }

  Future<void> _advance(PlaybackSession session, Duration duration) async {
    if (_advancing) return;
    _advancing = true;
    final notifier = ref.read(playbackSessionProvider.notifier);
    notifier.recordProgress(duration, duration, true);
    await notifier.playNext();
    if (mounted) setState(() => _advancing = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(playbackSessionProvider);
    final target = ref.watch(playerControllerProvider.select((s) => s.target));
    final ready = ref.watch(playerControllerProvider.select((s) => s.isReady));
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playerDurationProvider).value ?? Duration.zero;

    if (session == null || target == null || !ready || duration <= Duration.zero) {
      return const SizedBox.shrink();
    }

    final key = '${session.season}:${session.episode}:${target.source.url}';
    if (_loadedFor != key) {
      _loadedFor = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadChapters(key)));
    }

    _Segment? skip;
    for (final segment in _skips) {
      if (position >= segment.start && position < segment.end - const Duration(seconds: 2)) {
        skip = segment;
      }
    }
    if (skip == null && _skips.isEmpty && session.isEpisode) {
      if (position >= _fallbackIntroStart && position < _fallbackIntroEnd) {
        skip = _Segment(_fallbackIntroStart, position + _fallbackIntroSkip, 'Skip Intro');
      }
    }
    final skipKey = skip == null ? null : '$key:${skip.label}:${skip.start.inSeconds}';
    if (skipKey != null && _dismissed.contains(skipKey)) skip = null;

    final next = session.nextEpisode;
    final nextKey = '$key:next';
    final remaining = duration - position;
    final nextFrom = _creditsAt != null && _creditsAt! < duration
        ? duration - _creditsAt!
        : _nextLead;
    final lead = nextFrom > const Duration(minutes: 3) ? _nextLead : nextFrom;
    final showNext =
        next != null &&
        duration > const Duration(minutes: 5) &&
        remaining <= lead &&
        !_dismissed.contains(nextKey);

    if (showNext && remaining <= const Duration(milliseconds: 800) && !_advancing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_advance(session, duration)));
    }

    return Positioned(
      right: 28,
      bottom: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (skip != null && !showNext)
            _PillButton(
              icon: VesperIcons.skip,
              label: skip.label,
              autofocus: true,
              onTap: () {
                final target = skip!.end;
                _dismissed.add(skipKey!);
                unawaited(ref.read(playerControllerProvider.notifier).seekTo(target));
                widget.onInteract();
                setState(() {});
              },
            ),
          if (showNext)
            _NextCard(
              label: '${next.label}${next.title == null ? '' : '  ${next.title}'}',
              seconds: remaining.inSeconds.clamp(0, 99),
              onPlay: () => unawaited(_advance(session, duration)),
              onCancel: () => setState(() => _dismissed.add(nextKey)),
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      autofocus: autofocus,
      borderRadius: 6,
      scaleOnFocus: false,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xE6141414),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label, style: VesperType.button.copyWith(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.label,
    required this.seconds,
    required this.onPlay,
    required this.onCancel,
  });

  final String label;
  final int seconds;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF0141414),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Next episode in $seconds', style: VesperType.meta),
          const SizedBox(height: 4),
          Text(label, style: VesperType.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Row(
            children: [
              _PillButton(
                icon: VesperIcons.play,
                label: 'Play now',
                autofocus: true,
                onTap: onPlay,
              ),
              const SizedBox(width: 10),
              FocusableItem(
                onActivate: onCancel,
                borderRadius: 6,
                scaleOnFocus: false,
                semanticLabel: 'Cancel',
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Text('Cancel', style: VesperType.label),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../design/colors.dart';
import '../../../design/icons.dart';
import '../../../design/motion.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/focusable_item.dart';
import '../../../player/player_controller.dart';
import '../../../player/player_intents.dart';
import '../../../player/subtitle_style.dart';
import '../../../shell/input_mode.dart';

String describeAudioTrack(AudioTrack track) {
  if (track.id == 'no') return 'Off';
  if (track.id == 'auto') return 'Automatic';
  final parts = [
    track.title,
    track.language,
  ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
  if (parts.isEmpty) return 'Track ${track.id}';
  return parts.join(' - ');
}

String describeSubtitleTrack(SubtitleTrack track) {
  if (track.id == 'no') return 'Off';
  if (track.id == 'auto') return 'Automatic';
  final parts = [
    track.title,
    track.language,
  ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
  if (parts.isEmpty) return 'Track ${track.id}';
  return parts.join(' - ');
}

String describeVideoTrack(VideoTrack track) {
  if (track.id == 'no') return 'Off';
  if (track.id == 'auto') return 'Automatic';
  final height = track.h;
  if (height != null && height > 0) return '${height}p';
  final parts = [
    track.title,
    track.language,
  ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
  return parts.isEmpty ? 'Track ${track.id}' : parts.join(' - ');
}

class TrackPanel extends ConsumerWidget {
  const TrackPanel({
    super.key,
    required this.panel,
    required this.onClose,
    required this.onPanelChanged,
  });

  final PlayerPanel panel;
  final VoidCallback onClose;
  final ValueChanged<PlayerPanel> onPanelChanged;

  static const tabs = [
    (PlayerPanel.audio, 'Audio', VesperIcons.audioTrack),
    (PlayerPanel.subtitles, 'Subtitles', VesperIcons.subtitles),
    (PlayerPanel.quality, 'Quality', VesperIcons.quality),
    (PlayerPanel.speed, 'Speed', VesperIcons.speed),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    final sheetWidth = mode.isTouch ? double.infinity : 420.0;

    return Align(
      alignment: mode.isTouch ? Alignment.bottomCenter : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: sheetWidth,
          maxHeight: MediaQuery.sizeOf(context).height * (mode.isTouch ? 0.72 : 1.0),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: VesperColors.canvasDeep.withValues(alpha: 0.97),
            borderRadius: mode.isTouch
                ? const BorderRadius.vertical(top: Radius.circular(18))
                : null,
            border: const Border(left: BorderSide(color: VesperColors.divider)),
          ),
          child: SafeArea(
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PanelHeader(onClose: onClose),
                  _PanelTabs(active: panel, onChanged: onPanelChanged),
                  Flexible(child: _PanelBody(panel: panel)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
      child: Row(
        children: [
          const Expanded(child: Text('Playback', style: VesperType.sectionTitle)),
          FocusableItem(
            onActivate: onClose,
            borderRadius: 18,
            scaleOnFocus: false,
            semanticLabel: 'Close',
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(VesperIcons.close, size: 22, color: VesperColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.active, required this.onChanged});

  final PlayerPanel active;
  final ValueChanged<PlayerPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: TrackPanel.tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (panel, label, icon) = TrackPanel.tabs[index];
          final selected = panel == active;

          return FocusableItem(
            onActivate: () => onChanged(panel),
            borderRadius: 16,
            scaleOnFocus: false,
            semanticLabel: label,
            child: AnimatedContainer(
              duration: VesperMotion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? VesperColors.accent : VesperColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? VesperColors.canvas : VesperColors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: VesperType.label.copyWith(
                      color: selected ? VesperColors.canvas : VesperColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({required this.panel});

  final PlayerPanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final tracks = ref.watch(playerTracksProvider).value ?? controller.tracks;
    final player = controller.player;

    return switch (panel) {
      PlayerPanel.audio => _TrackList(
        items: [
          for (final track in tracks.audio)
            _TrackEntry(
              label: describeAudioTrack(track),
              selected: track == player.state.track.audio,
              onSelect: () => controller.selectAudio(track),
            ),
        ],
        emptyMessage: 'This stream reports a single built in audio track.',
      ),
      PlayerPanel.subtitles => _SubtitleSection(tracks: tracks.subtitle),
      PlayerPanel.quality => _TrackList(
        items: [
          for (final track in tracks.video)
            _TrackEntry(
              label: describeVideoTrack(track),
              selected: track == player.state.track.video,
              onSelect: () => controller.selectVideo(track),
            ),
        ],
        emptyMessage: 'Quality is chosen automatically for this stream.',
      ),
      PlayerPanel.speed => _SpeedList(controller: controller, current: player.state.rate),
      PlayerPanel.none => const SizedBox.shrink(),
    };
  }
}

class _TrackEntry {
  const _TrackEntry({required this.label, required this.selected, required this.onSelect});

  final String label;
  final bool selected;
  final VoidCallback onSelect;
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.items, required this.emptyMessage});

  final List<_TrackEntry> items;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
        child: Text(emptyMessage, style: VesperType.body),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return FocusableItem(
          onActivate: item.onSelect,
          borderRadius: 10,
          scaleOnFocus: false,
          semanticLabel: item.label,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    style: VesperType.bodyStrong.copyWith(
                      color: item.selected ? VesperColors.accent : VesperColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.selected)
                  const Icon(VesperIcons.check, size: 19, color: VesperColors.accent),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SpeedList extends StatelessWidget {
  const _SpeedList({required this.controller, required this.current});

  final PlayerControllerNotifier controller;
  final double current;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return _TrackList(
      items: [
        for (final rate in _rates)
          _TrackEntry(
            label: rate == 1.0 ? 'Normal' : '${rate}x',
            selected: (current - rate).abs() < 0.01,
            onSelect: () => controller.setSpeed(rate),
          ),
      ],
      emptyMessage: '',
    );
  }
}

class _SubtitleSection extends ConsumerWidget {
  const _SubtitleSection({required this.tracks});

  final List<SubtitleTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final playerState = ref.watch(playerControllerProvider);
    final style = playerState.subtitleStyle;
    final external = playerState.externalSubtitles;
    final activeExternal = playerState.activeExternal;
    final selected = controller.player.state.track.subtitle;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
      children: [
        if (external.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: Text('From this source', style: VesperType.label),
          ),
          for (final option in external)
            _SubtitleRow(
              label: option.name,
              selected: activeExternal == option.url,
              onSelect: () => controller.selectExternalSubtitle(option),
            ),
          _SubtitleRow(
            label: 'Off',
            selected: activeExternal == null && selected.id == 'no',
            onSelect: controller.clearSubtitles,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: VesperColors.divider),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 12, 10, 6),
            child: Text('Embedded in the file', style: VesperType.label),
          ),
        ],
        for (final track in tracks)
          FocusableItem(
            onActivate: () => controller.selectSubtitle(track),
            borderRadius: 10,
            scaleOnFocus: false,
            semanticLabel: describeSubtitleTrack(track),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      describeSubtitleTrack(track),
                      style: VesperType.bodyStrong.copyWith(
                        color: track == selected ? VesperColors.accent : VesperColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (track == selected)
                    const Icon(VesperIcons.check, size: 19, color: VesperColors.accent),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: VesperColors.divider),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('Appearance', style: VesperType.label),
        ),
        const SizedBox(height: 8),
        _OptionRow(
          label: 'Size',
          value: style.size.label,
          onPrevious: () => _cycleSize(controller, style, -1),
          onNext: () => _cycleSize(controller, style, 1),
        ),
        _OptionRow(
          label: 'Colour',
          value: style.colour.label,
          onPrevious: () => _cycleColour(controller, style, -1),
          onNext: () => _cycleColour(controller, style, 1),
        ),
        _OptionRow(
          label: 'Background',
          value: style.background.label,
          onPrevious: () => _cycleBackground(controller, style, -1),
          onNext: () => _cycleBackground(controller, style, 1),
        ),
        _OptionRow(
          label: 'Position',
          value: '${style.position}',
          onPrevious: () =>
              controller.applySubtitleStyle(style.copyWith(position: style.position - 5)),
          onNext: () => controller.applySubtitleStyle(style.copyWith(position: style.position + 5)),
        ),
        _OptionRow(
          label: 'Delay',
          value: '${(style.delayMs / 1000).toStringAsFixed(1)}s',
          onPrevious: () => controller.nudgeSubtitleDelay(-100),
          onNext: () => controller.nudgeSubtitleDelay(100),
        ),
      ],
    );
  }

  void _cycleSize(PlayerControllerNotifier controller, SubtitleStyle style, int delta) {
    const values = SubtitleSize.values;
    final next = (values.indexOf(style.size) + delta + values.length) % values.length;
    controller.applySubtitleStyle(style.copyWith(size: values[next]));
  }

  void _cycleColour(PlayerControllerNotifier controller, SubtitleStyle style, int delta) {
    const values = SubtitleColour.values;
    final next = (values.indexOf(style.colour) + delta + values.length) % values.length;
    controller.applySubtitleStyle(style.copyWith(colour: values[next]));
  }

  void _cycleBackground(PlayerControllerNotifier controller, SubtitleStyle style, int delta) {
    const values = SubtitleBackground.values;
    final next = (values.indexOf(style.background) + delta + values.length) % values.length;
    controller.applySubtitleStyle(style.copyWith(background: values[next]));
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.value,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final String value;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: VesperType.body)),
          _Stepper(icon: VesperIcons.chevronLeft, onTap: onPrevious, label: 'Decrease $label'),
          SizedBox(
            width: 92,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: VesperType.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _Stepper(icon: VesperIcons.chevronRight, onTap: onNext, label: 'Increase $label'),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      borderRadius: 14,
      scaleOnFocus: false,
      semanticLabel: label,
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: VesperColors.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: VesperColors.textSecondary),
      ),
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.label, required this.selected, required this.onSelect});

  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onSelect,
      borderRadius: 10,
      scaleOnFocus: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: VesperType.bodyStrong.copyWith(
                  color: selected ? VesperColors.accent : VesperColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected) const Icon(VesperIcons.check, size: 19, color: VesperColors.accent),
          ],
        ),
      ),
    );
  }
}

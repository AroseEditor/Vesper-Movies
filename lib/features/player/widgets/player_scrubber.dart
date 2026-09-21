import 'package:flutter/material.dart';

import '../../../design/colors.dart';
import '../../../design/motion.dart';
import '../../../design/typography.dart';

String formatDuration(Duration value) {
  final total = value.isNegative ? Duration.zero : value;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${total.inMinutes}:$seconds';
}

class PlayerScrubber extends StatefulWidget {
  const PlayerScrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.compact = false,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool compact;

  @override
  State<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<PlayerScrubber> {
  double? _dragValue;
  bool _focused = false;

  double get _progress {
    if (_dragValue != null) return _dragValue!;
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _commit(double value) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return;
    widget.onSeek(Duration(milliseconds: (total * value).round()));
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.duration - widget.position;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: _focused ? 6 : 4,
              activeTrackColor: VesperColors.accent,
              inactiveTrackColor: VesperColors.surfaceHover,
              secondaryActiveTrackColor: VesperColors.surfaceHover,
              thumbColor: VesperColors.accent,
              overlayColor: VesperColors.accent.withValues(alpha: 0.18),
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: _focused ? 10 : 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: _progress,
              onChanged: (value) => setState(() => _dragValue = value),
              onChangeEnd: (value) {
                _commit(value);
                setState(() => _dragValue = null);
              },
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedDefaultTextStyle(
                duration: VesperMotion.fast,
                style: VesperType.meta.copyWith(
                  color: VesperColors.textHover,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                child: Text(formatDuration(widget.position)),
              ),
              Text(
                widget.duration > Duration.zero ? '-${formatDuration(remaining)}' : '',
                style: VesperType.meta.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/colors.dart';
import '../../../design/motion.dart';
import '../../../design/typography.dart';
import '../../../player/preview_controller.dart';

const double _previewWidth = 176;
const double _previewHeight = 99;

String formatDuration(Duration value) {
  final total = value.isNegative ? Duration.zero : value;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${total.inMinutes}:$seconds';
}

class PlayerScrubber extends ConsumerStatefulWidget {
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
  ConsumerState<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends ConsumerState<PlayerScrubber> {
  final GlobalKey _trackKey = GlobalKey();

  double? _dragValue;
  bool _focused = false;

  double get _progress {
    if (_dragValue != null) return _dragValue!;
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration _at(double fraction) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return Duration.zero;
    return Duration(milliseconds: (total * fraction.clamp(0.0, 1.0)).round());
  }

  void _commit(double value) {
    if (widget.duration <= Duration.zero) return;
    widget.onSeek(_at(value));
  }

  double? _fractionAt(Offset globalPosition) {
    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return null;
    final local = box.globalToLocal(globalPosition);
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _preview(Offset globalPosition) {
    if (widget.duration <= Duration.zero) return;
    final fraction = _fractionAt(globalPosition);
    if (fraction == null) return;
    ref.read(scrubPreviewProvider.notifier).hover(_at(fraction));
  }

  void _clearPreview() => ref.read(scrubPreviewProvider.notifier).cancel();

  @override
  Widget build(BuildContext context) {
    final remaining = widget.duration - widget.position;
    final preview = ref.watch(scrubPreviewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview.isActive)
          _PreviewBubble(
            preview: preview,
            fraction: widget.duration <= Duration.zero
                ? 0
                : preview.position!.inMilliseconds / widget.duration.inMilliseconds,
            trackKey: _trackKey,
          ),
        MouseRegion(
          onHover: (event) => _preview(event.position),
          onExit: (_) => _clearPreview(),
          child: FocusableActionDetector(
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
                key: _trackKey,
                value: _progress,
                onChanged: (value) {
                  setState(() => _dragValue = value);
                  if (widget.duration > Duration.zero) {
                    ref.read(scrubPreviewProvider.notifier).hover(_at(value));
                  }
                },
                onChangeEnd: (value) {
                  _commit(value);
                  _clearPreview();
                  setState(() => _dragValue = null);
                },
              ),
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

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({required this.preview, required this.fraction, required this.trackKey});

  final PreviewState preview;
  final double fraction;
  final GlobalKey trackKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = constraints.maxWidth - _previewWidth;
        final left = span <= 0 ? 0.0 : (span * fraction.clamp(0.0, 1.0));
        final frame = preview.frame;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: _previewHeight + 26,
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: _previewWidth,
                        height: _previewHeight,
                        decoration: BoxDecoration(
                          color: VesperColors.player,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: VesperColors.surfaceHover),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x99000000),
                              blurRadius: 14,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: frame == null
                            ? const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(VesperColors.accent),
                                  ),
                                ),
                              )
                            : Image.memory(frame.bytes, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: _previewWidth,
                        child: Text(
                          formatDuration(preview.position ?? Duration.zero),
                          textAlign: TextAlign.center,
                          style: VesperType.meta.copyWith(
                            color: VesperColors.textHover,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

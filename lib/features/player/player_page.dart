import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../player/player_controller.dart';
import '../../player/player_intents.dart';
import '../../shell/input_mode.dart';
import 'widgets/player_scrubber.dart';
import 'widgets/track_panel.dart';

typedef PlaybackProgress = void Function(Duration position, Duration duration, bool completed);

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, this.onExit, this.onProgress});

  final VoidCallback? onExit;
  final PlaybackProgress? onProgress;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  final FocusNode _rootFocus = FocusNode(debugLabel: 'player');
  final FocusScopeNode _controlsScope = FocusScopeNode(debugLabel: 'player-controls');

  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  PlayerPanel _panel = PlayerPanel.none;

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.setFullScreen(next);
      } on Object catch (_) {
        return;
      }
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _restartHideTimer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (widget.onProgress != null) {
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _reportProgress());
    }
  }

  void _reportProgress({bool completed = false}) {
    final report = widget.onProgress;
    if (report == null) return;

    final player = ref.read(playerControllerProvider.notifier).player;
    final position = player.state.position;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;

    report(position, duration, completed || player.state.completed);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _reportProgress();
    _hideTimer?.cancel();
    _rootFocus.dispose();
    _controlsScope.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_panel != PlayerPanel.none) return;
    _hideTimer = Timer(VesperMotion.osdHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _restartHideTimer();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _restartHideTimer();
  }

  void _openPanel(PlayerPanel panel) {
    setState(() {
      _panel = panel;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  void _closePanel() {
    setState(() => _panel = PlayerPanel.none);
    _restartHideTimer();
  }

  void _exit() {
    if (_panel != PlayerPanel.none) {
      _closePanel();
      return;
    }
    if (_fullscreen) {
      unawaited(_toggleFullscreen());
      return;
    }
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Map<Type, Action<Intent>> _actions(PlayerControllerNotifier controller) {
    return {
      TogglePlayIntent: CallbackAction<TogglePlayIntent>(
        onInvoke: (_) {
          unawaited(controller.togglePlay());
          _showControls();
          return null;
        },
      ),
      SeekIntent: CallbackAction<SeekIntent>(
        onInvoke: (intent) {
          unawaited(controller.seekBy(intent.delta));
          _showControls();
          return null;
        },
      ),
      VolumeIntent: CallbackAction<VolumeIntent>(
        onInvoke: (intent) {
          unawaited(controller.nudgeVolume(intent.delta));
          _showControls();
          return null;
        },
      ),
      ToggleMuteIntent: CallbackAction<ToggleMuteIntent>(
        onInvoke: (_) {
          unawaited(controller.toggleMute());
          _showControls();
          return null;
        },
      ),
      SpeedIntent: CallbackAction<SpeedIntent>(
        onInvoke: (intent) {
          unawaited(controller.nudgeSpeed(intent.delta));
          _showControls();
          return null;
        },
      ),
      SubtitleDelayIntent: CallbackAction<SubtitleDelayIntent>(
        onInvoke: (intent) {
          unawaited(controller.nudgeSubtitleDelay(intent.deltaMs));
          _showControls();
          return null;
        },
      ),
      OpenPanelIntent: CallbackAction<OpenPanelIntent>(
        onInvoke: (intent) {
          _openPanel(intent.panel);
          return null;
        },
      ),
      ShowControlsIntent: CallbackAction<ShowControlsIntent>(
        onInvoke: (_) {
          _showControls();
          return null;
        },
      ),
      ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(
        onInvoke: (_) {
          unawaited(_toggleFullscreen());
          _showControls();
          return null;
        },
      ),
      ExitPlayerIntent: CallbackAction<ExitPlayerIntent>(
        onInvoke: (_) {
          _exit();
          return null;
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final state = ref.watch(playerControllerProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Shortcuts(
        shortcuts: playerShortcuts,
        child: Actions(
          actions: _actions(controller),
          child: Focus(
            focusNode: _rootFocus,
            autofocus: true,
            child: Scaffold(
              backgroundColor: VesperColors.player,
              body: MouseRegion(
                onHover: (_) {
                  if (mode.usesPointer) _showControls();
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(
                      controller: controller.videoController,
                      controls: NoVideoControls,
                      fit: BoxFit.contain,
                    ),
                    _GestureLayer(
                      mode: mode,
                      onTap: _toggleControls,
                      onSeek: (delta) {
                        unawaited(controller.seekBy(delta));
                        _showControls();
                      },
                    ),
                    AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: VesperMotion.normal,
                      curve: VesperMotion.enter,
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: FocusScope(
                          node: _controlsScope,
                          child: _Controls(
                            mode: mode,
                            fullscreen: _fullscreen,
                            onExit: _exit,
                            onOpenPanel: _openPanel,
                            onInteract: _showControls,
                            onToggleFullscreen: () => unawaited(_toggleFullscreen()),
                          ),
                        ),
                      ),
                    ),
                    if (_panel != PlayerPanel.none)
                      TrackPanel(
                        panel: _panel,
                        onClose: _closePanel,
                        onPanelChanged: (panel) => setState(() => _panel = panel),
                      ),
                    if (state.error != null) _PlayerError(message: state.error!, onExit: _exit),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GestureLayer extends StatelessWidget {
  const _GestureLayer({required this.mode, required this.onTap, required this.onSeek});

  final InputMode mode;
  final VoidCallback onTap;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    if (!mode.isTouch) {
      return GestureDetector(behavior: HitTestBehavior.translucent, onTap: onTap);
    }

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTap,
            onDoubleTap: () => onSeek(shortRewind),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTap,
            onDoubleTap: () => onSeek(shortSeek),
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({
    required this.mode,
    required this.fullscreen,
    required this.onExit,
    required this.onOpenPanel,
    required this.onInteract,
    required this.onToggleFullscreen,
  });

  final InputMode mode;
  final bool fullscreen;
  final VoidCallback onExit;
  final ValueChanged<PlayerPanel> onOpenPanel;
  final VoidCallback onInteract;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final target = ref.watch(playerControllerProvider).target;
    final position = ref.watch(playerPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playerDurationProvider).value ?? Duration.zero;
    final playing = ref.watch(playerPlayingProvider).value ?? false;
    final buffering = ref.watch(playerBufferingProvider).value ?? false;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000), Color(0xCC000000)],
          stops: [0.0, 0.42, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _TopBar(target: target, onExit: onExit),
            Expanded(
              child: Center(
                child: buffering
                    ? const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          color: VesperColors.accent,
                          strokeWidth: 3,
                        ),
                      )
                    : _CentreControls(
                        playing: playing,
                        onToggle: () {
                          unawaited(controller.togglePlay());
                          onInteract();
                        },
                        onSeek: (delta) {
                          unawaited(controller.seekBy(delta));
                          onInteract();
                        },
                      ),
              ),
            ),
            _BottomBar(
              mode: mode,
              fullscreen: fullscreen,
              onToggleFullscreen: onToggleFullscreen,
              position: position,
              duration: duration,
              onSeek: (value) {
                unawaited(controller.seekTo(value));
                onInteract();
              },
              onOpenPanel: onOpenPanel,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.target, required this.onExit});

  final PlaybackTarget? target;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 18, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FocusableItem(
            onActivate: onExit,
            borderRadius: 22,
            scaleOnFocus: false,
            semanticLabel: 'Back',
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(VesperIcons.back, size: 26),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  target?.title ?? '',
                  style: VesperType.bodyStrong.copyWith(fontSize: 17),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (target?.subtitle != null)
                  Text(
                    target!.subtitle!,
                    style: VesperType.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CentreControls extends StatelessWidget {
  const _CentreControls({required this.playing, required this.onToggle, required this.onSeek});

  final bool playing;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundButton(
          icon: VesperIcons.replay10,
          size: 34,
          onTap: () => onSeek(shortRewind),
          label: 'Back 10 seconds',
        ),
        const SizedBox(width: 28),
        _RoundButton(
          icon: playing ? VesperIcons.pause : VesperIcons.play,
          size: 48,
          filled: true,
          autofocus: true,
          onTap: onToggle,
          label: playing ? 'Pause' : 'Play',
        ),
        const SizedBox(width: 28),
        _RoundButton(
          icon: VesperIcons.forward10,
          size: 34,
          onTap: () => onSeek(shortSeek),
          label: 'Forward 10 seconds',
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.mode,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onOpenPanel,
  });

  final InputMode mode;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<PlayerPanel> onOpenPanel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(mode.isTouch ? 8 : 26, 0, mode.isTouch ? 8 : 26, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerScrubber(
            position: position,
            duration: duration,
            onSeek: onSeek,
            compact: mode.isTouch,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _LabelledButton(
                icon: VesperIcons.subtitles,
                label: 'Subtitles',
                onTap: () => onOpenPanel(PlayerPanel.subtitles),
              ),
              _LabelledButton(
                icon: VesperIcons.audioTrack,
                label: 'Audio',
                onTap: () => onOpenPanel(PlayerPanel.audio),
              ),
              _LabelledButton(
                icon: VesperIcons.quality,
                label: 'Quality',
                onTap: () => onOpenPanel(PlayerPanel.quality),
              ),
              _LabelledButton(
                icon: VesperIcons.speed,
                label: 'Speed',
                onTap: () => onOpenPanel(PlayerPanel.speed),
              ),
              const Spacer(),
              _FullscreenButton(fullscreen: fullscreen, onTap: onToggleFullscreen),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.label,
    this.filled = false,
    this.autofocus = false,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final String label;
  final bool filled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      autofocus: autofocus,
      borderRadius: size,
      semanticLabel: label,
      child: Container(
        width: size * 1.7,
        height: size * 1.7,
        decoration: BoxDecoration(
          color: filled ? VesperColors.accent : Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: size,
          color: filled ? VesperColors.canvas : VesperColors.textPrimary,
        ),
      ),
    );
  }
}

class _LabelledButton extends StatelessWidget {
  const _LabelledButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FocusableItem(
        onActivate: onTap,
        borderRadius: 10,
        scaleOnFocus: false,
        semanticLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21, color: VesperColors.textHover),
              const SizedBox(width: 7),
              Text(label, style: VesperType.label.copyWith(color: VesperColors.textHover)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.message, required this.onExit});

  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VesperColors.player.withValues(alpha: 0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(VesperIcons.warning, size: 44, color: VesperColors.textTertiary),
              const SizedBox(height: 14),
              const Text('This stream would not play', style: VesperType.sectionTitle),
              const SizedBox(height: 8),
              Text(
                message,
                style: VesperType.body,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 22),
              FocusableItem(
                onActivate: onExit,
                autofocus: true,
                borderRadius: 6,
                scaleOnFocus: false,
                semanticLabel: 'Go back',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    color: VesperColors.accent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text('Go back', style: VesperType.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton({required this.fullscreen, required this.onTap});

  final bool fullscreen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      borderRadius: 8,
      scaleOnFocus: false,
      semanticLabel: fullscreen ? 'Leave full screen' : 'Full screen',
      child: Tooltip(
        message: fullscreen ? 'Leave full screen  F' : 'Full screen  F',
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            fullscreen ? VesperIcons.fullscreenExit : VesperIcons.fullscreen,
            size: 24,
            color: VesperColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

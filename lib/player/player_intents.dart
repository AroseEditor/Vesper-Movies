import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class TogglePlayIntent extends Intent {
  const TogglePlayIntent();
}

class SeekIntent extends Intent {
  const SeekIntent(this.delta);

  final Duration delta;
}

class VolumeIntent extends Intent {
  const VolumeIntent(this.delta);

  final double delta;
}

class ToggleMuteIntent extends Intent {
  const ToggleMuteIntent();
}

class SpeedIntent extends Intent {
  const SpeedIntent(this.delta);

  final double delta;
}

class SubtitleDelayIntent extends Intent {
  const SubtitleDelayIntent(this.deltaMs);

  final int deltaMs;
}

class OpenPanelIntent extends Intent {
  const OpenPanelIntent(this.panel);

  final PlayerPanel panel;
}

class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

class ShowControlsIntent extends Intent {
  const ShowControlsIntent();
}

class NextEpisodeIntent extends Intent {
  const NextEpisodeIntent();
}

class ExitPlayerIntent extends Intent {
  const ExitPlayerIntent();
}

enum PlayerPanel { none, subtitles, audio, quality, speed }

const Duration shortSeek = Duration(seconds: 10);
const Duration longSeek = Duration(seconds: 60);
const Duration shortRewind = Duration(seconds: -10);
const Duration longRewind = Duration(seconds: -60);

final Map<ShortcutActivator, Intent> playerShortcuts = {
  const SingleActivator(LogicalKeyboardKey.space): const TogglePlayIntent(),
  const SingleActivator(LogicalKeyboardKey.keyK): const TogglePlayIntent(),
  const SingleActivator(LogicalKeyboardKey.enter): const TogglePlayIntent(),
  const SingleActivator(LogicalKeyboardKey.select): const TogglePlayIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPlayPause): const TogglePlayIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPlay): const TogglePlayIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPause): const TogglePlayIntent(),

  const SingleActivator(LogicalKeyboardKey.arrowLeft): const SeekIntent(shortRewind),
  const SingleActivator(LogicalKeyboardKey.keyJ): const SeekIntent(shortRewind),
  const SingleActivator(LogicalKeyboardKey.mediaRewind): const SeekIntent(shortRewind),
  const SingleActivator(LogicalKeyboardKey.arrowRight): const SeekIntent(shortSeek),
  const SingleActivator(LogicalKeyboardKey.keyL): const SeekIntent(shortSeek),
  const SingleActivator(LogicalKeyboardKey.mediaFastForward): const SeekIntent(shortSeek),

  const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): const SeekIntent(longRewind),
  const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): const SeekIntent(longSeek),

  const SingleActivator(LogicalKeyboardKey.arrowUp): const VolumeIntent(5),
  const SingleActivator(LogicalKeyboardKey.arrowDown): const VolumeIntent(-5),
  const SingleActivator(LogicalKeyboardKey.keyM): const ToggleMuteIntent(),

  const SingleActivator(LogicalKeyboardKey.bracketLeft): const SpeedIntent(-0.25),
  const SingleActivator(LogicalKeyboardKey.bracketRight): const SpeedIntent(0.25),

  const SingleActivator(LogicalKeyboardKey.keyZ): const SubtitleDelayIntent(-100),
  const SingleActivator(LogicalKeyboardKey.keyX): const SubtitleDelayIntent(100),

  const SingleActivator(LogicalKeyboardKey.keyT): const OpenPanelIntent(PlayerPanel.subtitles),
  const SingleActivator(LogicalKeyboardKey.keyA): const OpenPanelIntent(PlayerPanel.audio),

  const SingleActivator(LogicalKeyboardKey.keyF): const ToggleFullscreenIntent(),
  const SingleActivator(LogicalKeyboardKey.f11): const ToggleFullscreenIntent(),

  const SingleActivator(LogicalKeyboardKey.keyN): const NextEpisodeIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaTrackNext): const NextEpisodeIntent(),

  const SingleActivator(LogicalKeyboardKey.escape): const ExitPlayerIntent(),
  const SingleActivator(LogicalKeyboardKey.backspace): const ExitPlayerIntent(),
  const SingleActivator(LogicalKeyboardKey.goBack): const ExitPlayerIntent(),
};

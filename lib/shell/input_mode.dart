import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum InputMode { touch, desktop, tv }

extension InputModeX on InputMode {
  bool get isTv => this == InputMode.tv;
  bool get isTouch => this == InputMode.touch;
  bool get isDesktop => this == InputMode.desktop;
  bool get usesRail => this != InputMode.touch;
  bool get usesPointer => this == InputMode.desktop;

  double get gutter => switch (this) {
    InputMode.touch => 16,
    InputMode.desktop => 48,
    InputMode.tv => 58,
  };

  double get rowGap => switch (this) {
    InputMode.touch => 26,
    InputMode.desktop => 34,
    InputMode.tv => 42,
  };

  double get posterWidth => switch (this) {
    InputMode.touch => 124,
    InputMode.desktop => 168,
    InputMode.tv => 208,
  };

  double get textScale => isTv ? 1.18 : 1.0;
}

Future<InputMode> detectInputMode() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return InputMode.desktop;
  }
  if (Platform.isAndroid) {
    try {
      final native = await const MethodChannel('vesper/device').invokeMethod<bool>('isTelevision');
      if (native == true) return InputMode.tv;
      if (native == false) return InputMode.touch;
    } on Object catch (_) {}
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final features = info.systemFeatures;
      final tv =
          features.contains('android.software.leanback') ||
          features.contains('android.software.leanback_only') ||
          features.contains('amazon.hardware.fire_tv');
      return tv ? InputMode.tv : InputMode.touch;
    } on Object catch (_) {
      return InputMode.touch;
    }
  }
  return InputMode.touch;
}

InputMode startupInputMode = InputMode.touch;

class InputModeNotifier extends Notifier<InputMode> {
  @override
  InputMode build() {
    if (kIsWeb) return InputMode.desktop;
    return startupInputMode;
  }
}

final inputModeProvider = NotifierProvider<InputModeNotifier, InputMode>(InputModeNotifier.new);

class InputModeScope extends StatelessWidget {
  const InputModeScope({super.key, required this.mode, required this.child});

  final InputMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        navigationMode: mode.isTv ? NavigationMode.directional : NavigationMode.traditional,
        textScaler: TextScaler.linear(mode.textScale),
      ),
      child: child,
    );
  }
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SubtitleSize {
  small('Small', 34),
  medium('Medium', 46),
  large('Large', 58),
  huge('Huge', 72);

  const SubtitleSize(this.label, this.fontSize);

  final String label;
  final int fontSize;
}

enum SubtitleColour {
  white('White', 'FFFFFFFF'),
  yellow('Yellow', 'FFFFE066'),
  cyan('Cyan', 'FF3BE8C4'),
  soft('Soft grey', 'FFE5E5E5');

  const SubtitleColour(this.label, this.argb);

  final String label;
  final String argb;
}

enum SubtitleBackground {
  none('None', '00000000', 0),
  shadow('Shadow', '00000000', 3),
  box('Box', 'B3000000', 0),
  solid('Solid', 'FF000000', 0);

  const SubtitleBackground(this.label, this.argb, this.shadowSize);

  final String label;
  final String argb;
  final int shadowSize;
}

class SubtitleStyle {
  const SubtitleStyle({
    this.size = SubtitleSize.medium,
    this.colour = SubtitleColour.white,
    this.background = SubtitleBackground.shadow,
    this.borderSize = 3,
    this.position = 95,
    this.delayMs = 0,
    this.forceStyle = true,
  });

  final SubtitleSize size;
  final SubtitleColour colour;
  final SubtitleBackground background;
  final int borderSize;
  final int position;
  final int delayMs;
  final bool forceStyle;

  static const defaults = SubtitleStyle();

  static const minPosition = 50;
  static const maxPosition = 100;
  static const maxDelayMs = 20000;

  SubtitleStyle copyWith({
    SubtitleSize? size,
    SubtitleColour? colour,
    SubtitleBackground? background,
    int? borderSize,
    int? position,
    int? delayMs,
    bool? forceStyle,
  }) {
    return SubtitleStyle(
      size: size ?? this.size,
      colour: colour ?? this.colour,
      background: background ?? this.background,
      borderSize: (borderSize ?? this.borderSize).clamp(0, 8),
      position: (position ?? this.position).clamp(minPosition, maxPosition),
      delayMs: (delayMs ?? this.delayMs).clamp(-maxDelayMs, maxDelayMs),
      forceStyle: forceStyle ?? this.forceStyle,
    );
  }

  SubtitleStyle nudgeDelay(int deltaMs) => copyWith(delayMs: delayMs + deltaMs);

  Map<String, String> toMpvProperties() {
    return {
      'sub-ass-override': forceStyle ? 'force' : 'no',
      'sub-font-size': '${size.fontSize}',
      'sub-color': '#${colour.argb}',
      'sub-border-size': '${background == SubtitleBackground.shadow ? borderSize : 0}',
      'sub-border-color': '#FF000000',
      'sub-back-color': '#${background.argb}',
      'sub-shadow-offset': '${background.shadowSize}',
      'sub-pos': '$position',
      'sub-delay': '${delayMs / 1000}',
    };
  }

  Map<String, dynamic> toJson() => {
    'size': size.name,
    'colour': colour.name,
    'background': background.name,
    'borderSize': borderSize,
    'position': position,
    'forceStyle': forceStyle,
  };

  static SubtitleStyle fromJson(Map<String, dynamic> json) {
    return SubtitleStyle(
      size: _byName(SubtitleSize.values, json['size']) ?? SubtitleSize.medium,
      colour: _byName(SubtitleColour.values, json['colour']) ?? SubtitleColour.white,
      background:
          _byName(SubtitleBackground.values, json['background']) ?? SubtitleBackground.shadow,
      borderSize: json['borderSize'] is int ? json['borderSize'] as int : 3,
      position: json['position'] is int ? json['position'] as int : 95,
      forceStyle: json['forceStyle'] is bool ? json['forceStyle'] as bool : true,
    );
  }

  String encode() => jsonEncode(toJson());

  static SubtitleStyle decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } on FormatException {
      return defaults;
    }
    return defaults;
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

class SubtitleDefaultsNotifier extends Notifier<SubtitleStyle> {
  @override
  SubtitleStyle build() => SubtitleStyle.defaults;

  void set(SubtitleStyle style) => state = style;

  void cycleSize(int delta) {
    const values = SubtitleSize.values;
    final next = (values.indexOf(state.size) + delta + values.length) % values.length;
    state = state.copyWith(size: values[next]);
  }

  void cycleColour(int delta) {
    const values = SubtitleColour.values;
    final next = (values.indexOf(state.colour) + delta + values.length) % values.length;
    state = state.copyWith(colour: values[next]);
  }

  void cycleBackground(int delta) {
    const values = SubtitleBackground.values;
    final next = (values.indexOf(state.background) + delta + values.length) % values.length;
    state = state.copyWith(background: values[next]);
  }

  void nudgePosition(int delta) => state = state.copyWith(position: state.position + delta);
}

final subtitleDefaultsProvider = NotifierProvider<SubtitleDefaultsNotifier, SubtitleStyle>(
  SubtitleDefaultsNotifier.new,
);

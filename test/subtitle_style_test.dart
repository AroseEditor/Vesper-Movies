import 'package:flutter_test/flutter_test.dart';
import 'package:vesper_movies/player/player_intents.dart';
import 'package:vesper_movies/player/subtitle_style.dart';

void main() {
  group('mpv properties', () {
    test('force the ass override so the other properties take effect', () {
      final properties = SubtitleStyle.defaults.toMpvProperties();
      expect(properties['sub-ass-override'], 'force');
    });

    test('leave ass styling alone when the override is off', () {
      final properties = const SubtitleStyle(forceStyle: false).toMpvProperties();
      expect(properties['sub-ass-override'], 'no');
    });

    test('carry size, colour and position through', () {
      final properties = const SubtitleStyle(
        size: SubtitleSize.large,
        colour: SubtitleColour.cyan,
        position: 80,
      ).toMpvProperties();

      expect(properties['sub-font-size'], '58');
      expect(properties['sub-color'], '#FF3BE8C4');
      expect(properties['sub-pos'], '80');
    });

    test('use a border for shadow and a filled box for box', () {
      final shadow = const SubtitleStyle(
        background: SubtitleBackground.shadow,
        borderSize: 4,
      ).toMpvProperties();
      expect(shadow['sub-border-size'], '4');
      expect(shadow['sub-back-color'], '#00000000');

      final box = const SubtitleStyle(background: SubtitleBackground.box).toMpvProperties();
      expect(box['sub-border-size'], '0');
      expect(box['sub-back-color'], '#B3000000');
    });

    test('express delay in seconds', () {
      expect(const SubtitleStyle(delayMs: 500).toMpvProperties()['sub-delay'], '0.5');
      expect(const SubtitleStyle(delayMs: -1500).toMpvProperties()['sub-delay'], '-1.5');
      expect(SubtitleStyle.defaults.toMpvProperties()['sub-delay'], '0.0');
    });
  });

  group('bounds', () {
    test('clamp position into the readable range', () {
      expect(SubtitleStyle.defaults.copyWith(position: 10).position, SubtitleStyle.minPosition);
      expect(SubtitleStyle.defaults.copyWith(position: 400).position, SubtitleStyle.maxPosition);
    });

    test('clamp border size', () {
      expect(SubtitleStyle.defaults.copyWith(borderSize: -5).borderSize, 0);
      expect(SubtitleStyle.defaults.copyWith(borderSize: 99).borderSize, 8);
    });

    test('clamp delay to twenty seconds either way', () {
      expect(SubtitleStyle.defaults.copyWith(delayMs: 999999).delayMs, SubtitleStyle.maxDelayMs);
      expect(SubtitleStyle.defaults.copyWith(delayMs: -999999).delayMs, -SubtitleStyle.maxDelayMs);
    });

    test('nudge delay in steps', () {
      var style = SubtitleStyle.defaults;
      style = style.nudgeDelay(100);
      style = style.nudgeDelay(100);
      expect(style.delayMs, 200);
      expect(style.nudgeDelay(-500).delayMs, -300);
    });
  });

  group('persistence', () {
    test('survives an encode and decode round trip', () {
      const original = SubtitleStyle(
        size: SubtitleSize.huge,
        colour: SubtitleColour.yellow,
        background: SubtitleBackground.box,
        borderSize: 5,
        position: 70,
      );

      final restored = SubtitleStyle.decode(original.encode());

      expect(restored.size, SubtitleSize.huge);
      expect(restored.colour, SubtitleColour.yellow);
      expect(restored.background, SubtitleBackground.box);
      expect(restored.borderSize, 5);
      expect(restored.position, 70);
    });

    test('does not persist the per-session delay', () {
      final restored = SubtitleStyle.decode(const SubtitleStyle(delayMs: 4000).encode());
      expect(restored.delayMs, 0);
    });

    test('falls back to defaults on anything unreadable', () {
      expect(SubtitleStyle.decode(null).size, SubtitleSize.medium);
      expect(SubtitleStyle.decode('').size, SubtitleSize.medium);
      expect(SubtitleStyle.decode('not json').size, SubtitleSize.medium);
      expect(SubtitleStyle.decode('{"size":"gigantic"}').size, SubtitleSize.medium);
    });
  });

  group('shortcuts', () {
    test('bind both keyboard and remote keys to the same intents', () {
      final intents = playerShortcuts.values;

      expect(intents.whereType<TogglePlayIntent>().length, greaterThanOrEqualTo(5));
      expect(intents.whereType<SeekIntent>().length, greaterThanOrEqualTo(8));
      expect(intents.whereType<ExitPlayerIntent>().length, greaterThanOrEqualTo(2));
    });

    test('seek both directions by ten and sixty seconds', () {
      final deltas = playerShortcuts.values.whereType<SeekIntent>().map((e) => e.delta).toSet();

      expect(deltas, contains(const Duration(seconds: 10)));
      expect(deltas, contains(const Duration(seconds: -10)));
      expect(deltas, contains(const Duration(seconds: 60)));
      expect(deltas, contains(const Duration(seconds: -60)));
    });
  });
}

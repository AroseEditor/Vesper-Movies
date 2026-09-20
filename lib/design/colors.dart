import 'package:flutter/material.dart';

abstract final class VesperColors {
  static const canvas = Color(0xFF141414);
  static const canvasDeep = Color(0xFF0B0B0B);
  static const player = Color(0xFF000000);
  static const surface = Color(0xFF181818);
  static const surfaceRaised = Color(0xFF232323);
  static const surfaceHover = Color(0xFF2F2F2F);
  static const divider = Color(0xFF2A2A2A);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textHover = Color(0xFFE5E5E5);
  static const textSecondary = Color(0xFFB3B3B3);
  static const textTertiary = Color(0xFF808080);

  static const accent = Color(0xFF3BE8C4);
  static const accentAlt = Color(0xFF6C5CE7);
  static const accentDeep = Color(0xFF14B89A);

  static const danger = Color(0xFFE5484D);
  static const warning = Color(0xFFF5A524);
  static const success = Color(0xFF3BE8C4);

  static const scrim = Color(0xCC000000);

  static const heroFade = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xF2141414), Color(0x99141414), Color(0x00141414)],
    stops: [0.0, 0.45, 1.0],
  );

  static const heroBottomFade = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xFF141414), Color(0x00141414)],
    stops: [0.0, 0.85],
  );

  static const brandSweep = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [accentDeep, accent, accentAlt],
  );
}

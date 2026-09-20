import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class VesperType {
  static const _family = 'Inter';

  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 52,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.4,
    color: VesperColors.textPrimary,
  );

  static const heroTitle = TextStyle(
    fontFamily: _family,
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    color: VesperColors.textPrimary,
  );

  static const sectionTitle = TextStyle(
    fontFamily: _family,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: VesperColors.textPrimary,
  );

  static const cardTitle = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: VesperColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: VesperColors.textSecondary,
  );

  static const bodyStrong = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: VesperColors.textPrimary,
  );

  static const meta = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: VesperColors.textTertiary,
  );

  static const label = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: VesperColors.textSecondary,
  );

  static const button = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    color: VesperColors.canvas,
  );

  static TextStyle scaledForTv(TextStyle base) =>
      base.copyWith(fontSize: (base.fontSize ?? 14) * 1.25);
}

import 'package:flutter/material.dart';

abstract final class VesperMotion {
  static const instant = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);
  static const deliberate = Duration(milliseconds: 620);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const standard = Curves.easeInOutCubic;
  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const overshoot = Cubic(0.34, 1.3, 0.64, 1.0);

  static const focusScale = 1.06;
  static const pressScale = 0.97;

  static const osdHideDelay = Duration(seconds: 3);
  static const scrollIntoViewAlignment = 0.08;
}

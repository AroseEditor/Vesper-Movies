import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/colors.dart';

class VRibbonPainter extends CustomPainter {
  const VRibbonPainter({
    required this.assemble,
    required this.solidify,
    required this.sweep,
    required this.barCount,
  });

  final double assemble;
  final double solidify;
  final double sweep;
  final int barCount;

  static const _armSpread = 0.34;
  static const _armHeight = 0.30;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halfW = size.shortestSide * _armSpread;
    final halfH = size.shortestSide * _armHeight;

    final apex = Offset(center.dx, center.dy + halfH);
    final leftTop = Offset(center.dx - halfW, center.dy - halfH);
    final rightTop = Offset(center.dx + halfW, center.dy - halfH);

    final perArm = barCount ~/ 2;
    final armLength = (apex - leftTop).distance;
    final barLength = armLength / perArm * 1.22;
    final barWidth = size.shortestSide * 0.052;

    final shader = VesperColors.brandSweep.createShader(
      Rect.fromCenter(center: center, width: halfW * 2.4, height: halfH * 2.4),
    );

    for (var arm = 0; arm < 2; arm++) {
      final start = arm == 0 ? leftTop : rightTop;
      final direction = apex - start;
      final angle = math.atan2(direction.dy, direction.dx);

      for (var i = 0; i < perArm; i++) {
        final index = arm * perArm + i;
        final slot = (i + 0.5) / perArm;

        final stagger = index / barCount * 0.35;
        final local = ((assemble - stagger) / 0.65).clamp(0.0, 1.0).toDouble();
        if (local <= 0) continue;
        final eased = Curves.easeOutCubic.transform(local);

        final spread = (index / (barCount - 1)) * 2 - 1;
        final origin = Offset(
          center.dx + spread * halfW * 1.75,
          center.dy - size.height * 0.9 * (1 - eased),
        );
        final target = Offset.lerp(start, apex, slot)!;

        final position = Offset.lerp(origin, target, eased)!;
        final rotation = ui.lerpDouble(0, angle + math.pi / 2, eased)!;
        final opacity = (eased * (0.45 + 0.55 * solidify)).clamp(0.0, 1.0);

        canvas.save();
        canvas.translate(position.dx, position.dy);
        canvas.rotate(rotation);

        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: barWidth,
            height: barLength * (0.55 + 0.45 * eased),
          ),
          Radius.circular(barWidth * 0.35),
        );

        canvas.drawRRect(
          rect,
          Paint()
            ..shader = shader
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + 10 * solidify)
            ..color = VesperColors.accent.withValues(alpha: opacity * 0.5),
        );

        canvas.drawRRect(
          rect,
          Paint()
            ..shader = shader
            ..color = VesperColors.accent.withValues(alpha: opacity),
        );

        canvas.restore();
      }
    }

    if (sweep > 0) {
      final path = Path()
        ..moveTo(leftTop.dx, leftTop.dy)
        ..lineTo(apex.dx, apex.dy)
        ..lineTo(rightTop.dx, rightTop.dy);

      final travel = ui.lerpDouble(-halfW * 2.2, halfW * 2.2, sweep)!;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = barWidth * 0.9
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..shader = ui.Gradient.linear(
            Offset(center.dx + travel - halfW * 0.5, center.dy),
            Offset(center.dx + travel + halfW * 0.5, center.dy),
            [
              VesperColors.accent.withValues(alpha: 0),
              Colors.white.withValues(
                alpha: 0.85 * (1 - (sweep - 0.5).abs() * 2).clamp(0.0, 1.0),
              ),
              VesperColors.accent.withValues(alpha: 0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(VRibbonPainter old) =>
      old.assemble != assemble ||
      old.solidify != solidify ||
      old.sweep != sweep ||
      old.barCount != barCount;
}

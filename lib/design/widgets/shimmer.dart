import 'package:flutter/material.dart';

import '../colors.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.width, required this.height, this.borderRadius = 6});

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                begin: Alignment(-1.6 + t * 3.2, -0.3),
                end: Alignment(-0.6 + t * 3.2, 0.3),
                colors: const [
                  VesperColors.surface,
                  VesperColors.surfaceHover,
                  VesperColors.surface,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

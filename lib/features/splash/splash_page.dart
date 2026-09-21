import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/colors.dart';
import '../../design/motion.dart';
import 'v_ribbon_painter.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({
    super.key,
    required this.onComplete,
    this.abbreviated = false,
  });

  final VoidCallback onComplete;
  final bool abbreviated;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _assemble;
  late final Animation<double> _solidify;
  late final Animation<double> _sweep;
  late final Animation<double> _ribbonFade;
  late final Animation<double> _wordmark;
  late final Animation<double> _wordmarkScale;
  late final Animation<double> _exit;

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.abbreviated
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 2800),
    );

    _assemble = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.46, curve: Curves.linear),
    );
    _solidify = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.36, 0.58, curve: Curves.easeOutCubic),
    );
    _sweep = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.46, 0.70, curve: Curves.easeInOutCubic),
    );
    _ribbonFade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.62, 0.80, curve: Curves.easeInCubic),
      ),
    );
    _wordmark = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 0.84, curve: Curves.easeOutCubic),
    );
    _wordmarkScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.60, 0.95, curve: VesperMotion.emphasized),
      ),
    );
    _exit = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.92, 1.0, curve: Curves.easeInCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _controller.forward();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onComplete();
  }

  void _skip() {
    if (_finished) return;
    _controller.stop();
    _finish();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          _skip();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: ColoredBox(
          color: VesperColors.canvasDeep,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _exit.value,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.9,
                          colors: [Color(0xFF0E1A18), Color(0xFF080808)],
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: _ribbonFade.value,
                      child: CustomPaint(
                        painter: VRibbonPainter(
                          assemble: _assemble.value,
                          solidify: _solidify.value,
                          sweep: _sweep.value,
                          barCount: 14,
                        ),
                      ),
                    ),
                    Center(
                      child: Opacity(
                        opacity: _wordmark.value,
                        child: Transform.scale(
                          scale: _wordmarkScale.value,
                          child: FractionallySizedBox(
                            widthFactor: 0.62,
                            child: Image.asset(
                              'assets/icon.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

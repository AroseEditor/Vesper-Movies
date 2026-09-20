import 'package:flutter/material.dart';

import '../colors.dart';
import '../motion.dart';

class FocusableItem extends StatefulWidget {
  const FocusableItem({
    super.key,
    required this.child,
    this.onActivate,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = 6,
    this.scaleOnFocus = true,
    this.glow = true,
    this.ensureVisible = true,
    this.alignment = VesperMotion.scrollIntoViewAlignment,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final double borderRadius;
  final bool scaleOnFocus;
  final bool glow;
  final bool ensureVisible;
  final double alignment;
  final String? semanticLabel;

  @override
  State<FocusableItem> createState() => _FocusableItemState();
}

class _FocusableItemState extends State<FocusableItem> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  bool get _active => _focused || _hovered;

  void _handleFocusHighlight(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
    widget.onFocusChange?.call(value);
    if (value && widget.ensureVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final object = context.findRenderObject();
        if (object == null) return;
        Scrollable.ensureVisible(
          context,
          alignment: widget.alignment,
          duration: VesperMotion.normal,
          curve: VesperMotion.enter,
        );
      });
    }
  }

  void _handleHoverHighlight(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _activate() {
    widget.onActivate?.call();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final scale = _pressed
        ? VesperMotion.pressScale
        : (_active && widget.scaleOnFocus ? VesperMotion.focusScale : 1.0);

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onShowFocusHighlight: _handleFocusHighlight,
      onShowHoverHighlight: _handleHoverHighlight,
      mouseCursor: widget.onActivate == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Semantics(
          label: widget.semanticLabel,
          button: widget.onActivate != null,
          focused: _focused,
          child: AnimatedScale(
            scale: scale,
            duration: VesperMotion.fast,
            curve: VesperMotion.overshoot,
            child: AnimatedContainer(
              duration: VesperMotion.fast,
              curve: VesperMotion.enter,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _active ? VesperColors.accent : Colors.transparent,
                  width: 2,
                ),
                boxShadow: _active && widget.glow
                    ? const [
                        BoxShadow(
                          color: Color(0x593BE8C4),
                          blurRadius: 24,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

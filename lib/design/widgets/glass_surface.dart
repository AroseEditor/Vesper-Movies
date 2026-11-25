import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

// Recipe matched 1:1 against the reference liquid-glass implementation
// (glass-apply.css / glass-surface.js): neutral white tint at low alpha,
// small blur, a thin bright rim, and a soft outer shadow for depth — never
// a brand-coloured tint.
abstract final class VesperGlass {
  static const settings = LiquidGlassSettings(
    glassColor: Color(0x14FFFFFF),
    thickness: 18,
    blur: 3,
    chromaticAberration: 0.02,
    refractiveIndex: 1.15,
    saturation: 1.4,
    lightIntensity: 0.5,
    fresnelStrength: 1.3,
    shadowElevation: 1.2,
  );

  static const raised = LiquidGlassSettings(
    glassColor: Color(0x1FFFFFFF),
    thickness: 22,
    blur: 3,
    chromaticAberration: 0.025,
    refractiveIndex: 1.18,
    saturation: 1.45,
    lightIntensity: 0.55,
    fresnelStrength: 1.4,
    shadowElevation: 1.4,
  );

  static const panel = LiquidGlassSettings(
    glassColor: Color(0x80141419),
    thickness: 30,
    blur: 20,
    frost: 8,
    chromaticAberration: 0.02,
    refractiveIndex: 1.15,
    saturation: 1.4,
    lightIntensity: 0.5,
    fresnelStrength: 1.2,
    shadowElevation: 1.6,
    platformViewMode: PlatformViewGlassMode.passthrough,
  );

  static const overVideo = LiquidGlassSettings(
    glassColor: Color(0x14FFFFFF),
    thickness: 18,
    blur: 3,
    chromaticAberration: 0.02,
    refractiveIndex: 1.15,
    saturation: 1.4,
    lightIntensity: 0.5,
    fresnelStrength: 1.3,
    shadowElevation: 1.2,
    platformViewMode: PlatformViewGlassMode.passthrough,
  );

  // the sliding selection pill — lighter and glossier than static chrome
  static const pill = LiquidGlassSettings(
    glassColor: Color(0x24FFFFFF),
    thickness: 20,
    blur: 2,
    chromaticAberration: 0.03,
    refractiveIndex: 1.2,
    saturation: 1.3,
    lightIntensity: 0.6,
    fresnelStrength: 1.6,
    shadowElevation: 1.3,
  );

  static const rimColor = Color(0x1FFFFFFF);
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.shape,
    this.settings,
    this.overVideo = false,
    this.raised = false,
    this.isInteractive = false,
    this.clipExpansion = EdgeInsets.zero,
    this.borderRadius,
    this.showRim = true,
  });

  final Widget child;
  final LiquidShape? shape;
  final LiquidGlassSettings? settings;
  final bool overVideo;
  final bool raised;
  final bool isInteractive;
  final EdgeInsets clipExpansion;
  final double? borderRadius;
  final bool showRim;

  @override
  Widget build(BuildContext context) {
    final resolved =
        settings ??
        (overVideo ? VesperGlass.overVideo : (raised ? VesperGlass.raised : VesperGlass.settings));
    final radius = borderRadius ?? 18;
    // A surface sampling a live video backdrop pays for a fresh BackdropFilter
    // + shader pass every decoded frame. Keep real glass everywhere else;
    // only over actively-playing video does it drop to the blur-only tier so
    // playback FPS never competes with the shader for GPU time.
    final glass = AdaptiveGlass(
      shape: shape ?? LiquidRoundedSuperellipse(borderRadius: radius),
      settings: resolved,
      quality: overVideo ? GlassQuality.minimal : GlassQuality.premium,
      isInteractive: isInteractive,
      clipExpansion: clipExpansion,
      platformViewBackdrop: overVideo,
      child: child,
    );
    if (!showRim || shape != null) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: VesperGlass.rimColor),
      ),
      child: glass,
    );
  }
}

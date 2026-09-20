import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'typography.dart';

abstract final class VesperTheme {
  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: VesperColors.accent,
      onPrimary: VesperColors.canvas,
      secondary: VesperColors.accentAlt,
      onSecondary: VesperColors.textPrimary,
      surface: VesperColors.surface,
      onSurface: VesperColors.textPrimary,
      error: VesperColors.danger,
      onError: VesperColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: VesperColors.canvas,
      canvasColor: VesperColors.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerColor: VesperColors.divider,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: VesperType.display,
        headlineLarge: VesperType.heroTitle,
        titleLarge: VesperType.sectionTitle,
        titleMedium: VesperType.cardTitle,
        bodyLarge: VesperType.bodyStrong,
        bodyMedium: VesperType.body,
        bodySmall: VesperType.meta,
        labelLarge: VesperType.button,
        labelMedium: VesperType.label,
      ),
      iconTheme: const IconThemeData(color: VesperColors.textPrimary, size: 22),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(VesperColors.surfaceHover),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: VesperColors.surfaceRaised,
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: VesperType.meta,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: VesperColors.canvas,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}

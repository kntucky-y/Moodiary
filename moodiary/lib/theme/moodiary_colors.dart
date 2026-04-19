import 'package:flutter/material.dart';

extension MoodiaryColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get mdScaffold =>
      isDarkMode ? const Color(0xFF0C0F17) : const Color(0xFFF7F5F2);
  Color get mdSurface => isDarkMode ? const Color(0xFF1B1F2C) : Colors.white;
  Color get mdSecondarySurface =>
      isDarkMode ? const Color(0xFF1F2534) : const Color(0xFFF0E8DC);
  Color get mdCardGlow => isDarkMode
      ? Colors.black.withValues(alpha: 0.4)
      : Colors.black.withValues(alpha: 0.05);
  Color get mdPrimaryText =>
      isDarkMode ? Colors.white : const Color(0xFF1A1A2E);
  Color get mdSecondaryText => isDarkMode
      ? Colors.white.withValues(alpha: 0.75)
      : const Color(0xFF8A8A8D);
  Color get mdInputFill => isDarkMode ? const Color(0xFF23283A) : Colors.white;
  Color get mdInputBorder =>
      isDarkMode ? Colors.white24 : const Color(0xFFDDDDDD);
  Color get mdAccentPurple => const Color(0xFFA076F9);

  Color get mdGlassSurface => isDarkMode
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.34);
  Color get mdGlassSurfaceStrong => isDarkMode
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.50);
  Color get mdGlassBorder => isDarkMode
      ? Colors.white.withValues(alpha: 0.22)
      : Colors.white.withValues(alpha: 0.34);
  Color get mdGlassHighlight => isDarkMode
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.16);
  Color get mdOverlayBarrier => isDarkMode
      ? Colors.black.withValues(alpha: 0.34)
      : Colors.black.withValues(alpha: 0.16);

  double get mdGlassBlurSmall => 8;
  double get mdGlassBlurMedium => 18;
  double get mdGlassBlurLarge => 24;

  Color get mdGlassButtonSurface => isDarkMode
      ? Colors.white.withValues(alpha: 0.16)
      : Colors.white.withValues(alpha: 0.54);
  Color get mdGlassButtonPressedSurface => isDarkMode
      ? Colors.white.withValues(alpha: 0.24)
      : Colors.white.withValues(alpha: 0.66);
  Color get mdGlassButtonDisabledSurface => isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.32);
  Color get mdGlassButtonForeground =>
      isDarkMode ? Colors.white : const Color(0xFF1A1A2E);
  double get mdRadiusSm => 12;
  double get mdRadiusMd => 16;
  double get mdRadiusLg => 20;
  double get mdRadiusXl => 24;
  double get mdHeaderCollapseOffset => 18;
  Duration get mdHeaderCollapseDuration => const Duration(milliseconds: 260);
  Duration get mdHeaderFadeDuration => const Duration(milliseconds: 220);

  List<BoxShadow> get mdGlassShadows => [
    BoxShadow(
      color: isDarkMode
          ? Colors.black.withValues(alpha: 0.25)
          : Colors.black.withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: mdGlassHighlight,
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  Gradient get mdGlassHeroGradient => LinearGradient(
    colors: [
      mdSecondarySurface.withValues(alpha: isDarkMode ? 0.82 : 0.92),
      mdGlassSurfaceStrong,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

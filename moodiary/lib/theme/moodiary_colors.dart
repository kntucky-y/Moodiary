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
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.68);
  Color get mdGlassSurfaceStrong => isDarkMode
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.82);
  Color get mdGlassBorder => isDarkMode
      ? Colors.white.withValues(alpha: 0.2)
      : Colors.white.withValues(alpha: 0.75);
  Color get mdGlassHighlight => isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.35);
  Color get mdOverlayBarrier => isDarkMode
      ? Colors.black.withValues(alpha: 0.5)
      : Colors.black.withValues(alpha: 0.24);

  double get mdGlassBlurMedium => 14;
  double get mdRadiusSm => 12;
  double get mdRadiusMd => 16;
  double get mdRadiusLg => 20;
  double get mdRadiusXl => 24;

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

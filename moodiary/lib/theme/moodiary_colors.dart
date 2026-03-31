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
}

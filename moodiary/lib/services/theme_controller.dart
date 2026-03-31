import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();
  static const _prefKey = 'app_theme_mode';
  static const _defaultMode = ThemeMode.light;

  final ValueNotifier<ThemeMode> _modeNotifier = ValueNotifier<ThemeMode>(
    _defaultMode,
  );

  ValueListenable<ThemeMode> get listenable => _modeNotifier;
  ThemeMode get mode => _modeNotifier.value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    _modeNotifier.value = _fromString(stored) ?? _defaultMode;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_modeNotifier.value == mode) return;
    _modeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _toString(mode));
  }

  Future<void> toggleDark(bool enabled) async {
    await setMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> resetToDefault() async {
    _modeNotifier.value = _defaultMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  ThemeMode? _fromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

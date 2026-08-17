import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_colors.dart';

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;

  ThemeService._internal() {
    // 👇 Écoute les changements de thème du téléphone en temps réel
    PlatformDispatcher.instance.onPlatformBrightnessChanged = () {
      _updateToSystemThemeIfNeeded();
    };
  }

  bool _isDarkMode = false;
  bool _isUserDefined = false;

  bool get isDarkMode => _isDarkMode;

  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.containsKey(_themeKey)) {
        _isDarkMode = prefs.getBool(_themeKey)!;
        _isUserDefined = true;
      } else {
        // Mode automatique par défaut
        _isDarkMode = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
        _isUserDefined = false;
      }
      notifyListeners();
    } catch (e) {
      _isDarkMode = false;
    }
  }

  void _updateToSystemThemeIfNeeded() {
    if (!_isUserDefined) {
      final isSystemDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
      if (_isDarkMode != isSystemDark) {
        _isDarkMode = isSystemDark;
        notifyListeners();
      }
    }
  }

  Future<void> setThemeMode(bool isDark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isSystemDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;

      // 👇 ASTUCE : Si l'utilisateur choisit le même thème que son téléphone,
      // on repasse en mode "Automatique" (on oublie son choix forcé)
      if (isDark == isSystemDark) {
        await prefs.remove(_themeKey);
        _isUserDefined = false;
      } else {
        await prefs.setBool(_themeKey, isDark);
        _isUserDefined = true;
      }

      _isDarkMode = isDark;
      notifyListeners();
    } catch (e) {
      // Ignorer
    }
  }

  void toggleTheme() {
    setThemeMode(!_isDarkMode);
  }

  ThemeData getThemeData() {
    return _isDarkMode ? AppColors.darkTheme : AppColors.lightTheme;
  }

  Color get background => _isDarkMode ? const Color(0xFF0F0F1A) : AppColors.background;
  Color get cardBackground => _isDarkMode ? const Color(0xFF1E1E2E) : AppColors.cardBackground;
  Color get backgroundAlt => _isDarkMode ? const Color(0xFF2D2D44) : AppColors.backgroundAlt;
  Color get textPrimary => _isDarkMode ? Colors.white : AppColors.textPrimary;
  Color get textSecondary => _isDarkMode ? const Color(0xFFB0B0C0) : AppColors.textSecondary;
  Color get textHint => _isDarkMode ? const Color(0xFF6B7280) : AppColors.textHint;
  Color get inputBorder => _isDarkMode ? const Color(0xFF3D3D5C) : AppColors.inputBorder;
  Color get inputBackground => _isDarkMode ? const Color(0xFF2D2D44) : AppColors.inputBackground;
  List<BoxShadow> get cardShadow => _isDarkMode ? AppColors.cardShadowDark : AppColors.cardShadow;
}
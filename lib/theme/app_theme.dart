import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    primaryColor: const Color(0xFF4361EE),
    scaffoldBackgroundColor: const Color(0xFFF8F9FC),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1A1E2B),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4361EE),
      secondary: Color(0xFF2B2D42),
    ),
  );
}

// Couleurs personnalisées
class AppColors {
  static const Color bleuCiel = Color(0xFF4361EE);
  static const Color bleuProfond = Color(0xFF1A1E2B);
  static const Color bleuNuit = Color(0xFF2B2D42);
  static const Color noirProfond = Color(0xFF1A1E2B);
  static const Color blancPur = Color(0xFFF8F9FC);
  static const Color rouge = Color(0xFFF44336);
  static const Color vert = Color(0xFF4CAF50);
  static const Color violet = Color(0xFF7B4DFF);
}
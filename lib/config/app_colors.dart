import 'package:flutter/material.dart';

class AppColors {
  // ============ COULEURS PRINCIPALES (Logo) ============
  /// Jaune-vert du logo (couleur principale)
  static const Color primary = Color(0xFF7CB342);
  static const Color primaryLight = Color(0xFFAED581);
  static const Color primaryDark = Color(0xFF558B2F);

  /// Jaune du logo
  static const Color secondary = Color(0xFFFFC107);
  static const Color secondaryLight = Color(0xFFFFE082);
  static const Color secondaryDark = Color(0xFFFFA000);

  // ============ COULEURS DE FOND ============
  /// Fond principal - Blanc cassé pour un look épuré
  static const Color background = Color(0xFFF8FAFC);

  /// Fond des cartes - Blanc pur
  static const Color cardBackground = Color(0xFFFFFFFF);

  /// Fond alternatif - Gris très clair
  static const Color backgroundAlt = Color(0xFFF1F5F9);

  // ============ COULEURS DE TEXTE ============
  /// Texte principal - Gris foncé pour une bonne lisibilité
  static const Color textPrimary = Color(0xFF1A202C);

  /// Texte secondaire - Gris moyen
  static const Color textSecondary = Color(0xFF4A5568);

  /// Texte d'aide - Gris clair
  static const Color textHint = Color(0xFFA0AEC0);

  /// Texte sur fond coloré (toujours blanc)
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ============ COULEURS DES CHAMPS ============
  /// Bordure des champs - Gris clair
  static const Color inputBorder = Color(0xFFCBD5E1);

  /// Focus des champs - Vert primaire
  static const Color inputFocus = Color(0xFF7CB342);

  /// Fond des champs - Blanc
  static const Color inputBackground = Color(0xFFFFFFFF);

  /// Label des champs - Gris
  static const Color inputLabel = Color(0xFF4A5568);

  // ============ COULEURS D'ÉTAT ============
  /// Succès - Vert
  static const Color success = Color(0xFF38A169);
  static const Color successLight = Color(0xFFC6F6D5);

  /// Erreur - Rouge élégant
  static const Color error = Color(0xFFE53E3E);
  static const Color errorLight = Color(0xFFFED7D7);

  /// Warning - Orange
  static const Color warning = Color(0xFFED8936);
  static const Color warningLight = Color(0xFFFEEBC8);

  // ============ OMBRES ============
  /// Ombres douces pour les cartes
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 10,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 20,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  // ============ OMBRES POUR THÈME SOMBRE ============
  static const List<BoxShadow> cardShadowDark = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 10,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x20000000),
      blurRadius: 20,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  // ============ DÉGRADÉS ============
  /// Dégradé pour le bouton principal
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7CB342),
      Color(0xFF558B2F),
    ],
  );

  /// Dégradé pour l'icône de sécurité
  static const LinearGradient iconGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7CB342),
      Color(0xFFFFC107),
    ],
  );

  // ============ THÈME CLAIR ============
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: cardBackground,
        background: background,
        error: error,
        onPrimary: textOnPrimary,
        onSecondary: textOnPrimary,
        onSurface: textPrimary,
        onBackground: textPrimary,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Poppins',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: inputFocus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        labelStyle: const TextStyle(color: inputLabel),
        hintStyle: TextStyle(color: textHint),
        errorStyle: TextStyle(color: error, fontSize: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ============ THÈME SOMBRE ============
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: const Color(0xFF1E1E2E),
        background: const Color(0xFF0F0F1A),
        error: error,
        onPrimary: textOnPrimary,
        onSecondary: textOnPrimary,
        onSurface: Colors.white,
        onBackground: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      fontFamily: 'Poppins',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2D2D44),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3D3D5C)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3D3D5C)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        hintStyle: const TextStyle(color: Color(0xFF6B7280)),
        errorStyle: TextStyle(color: error, fontSize: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }



}
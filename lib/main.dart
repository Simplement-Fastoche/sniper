import 'package:flutter/material.dart';
// 👇 1. Ajoute cet import pour les dates
import 'package:intl/date_symbol_data_local.dart';

import 'package:sniper/screens/auth_check_screen.dart';
import 'package:sniper/services/theme_service.dart';
import 'package:sniper/theme/app_theme.dart'; // Pour le thème par défaut

// 👇 2. Ajoute "async" à ta fonction main
void main() async {
  // 👇 3. Assure-toi que Flutter est bien initialisé avant de lancer des fonctions asynchrones
  WidgetsFlutterBinding.ensureInitialized();

  // 👇 4. Initialise les données locales pour le français
  await initializeDateFormatting('fr_FR', null);

  // 👇 5. Charger le thème sauvegardé
  final themeService = ThemeService();
  await themeService.loadTheme();

  runApp(MyApp(themeService: themeService));
}

class MyApp extends StatelessWidget {
  final ThemeService themeService;

  const MyApp({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sniper App',
      debugShowCheckedModeBanner: false,
      theme: themeService.getThemeData(),
      // 👇 Garde AuthCheckScreen comme page d'accueil
      home: const AuthCheckScreen(),
    );
  }
}
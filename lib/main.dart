import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sniper/screens/activation_screen.dart';
import 'package:sniper/screens/auth_check_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';

import 'package:intl/date_symbol_data_local.dart'; // Import crucial
import 'package:intl/intl.dart';

// AJOUTE LE MOT-CLÉ "async" ICI
void main() async {
  // Assure-toi que les bindings sont initialisés
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise les données de localisation pour le français
  await initializeDateFormatting('fr_FR', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Payment App',
      theme: AppTheme.lightTheme,

      // L'application démarre ICI :
      home: const AuthCheckScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'activation_screen.dart';
import 'dashboard_screen.dart';

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('auth_token');

    // On ajoute un petit délai artificiel pour laisser le temps
    // à l'interface de s'afficher (optionnel, pour l'effet "Splash Screen")
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // Un token existe -> Go Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      // Aucun token -> Go Activation
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ActivationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // On utilise un Container pour appliquer le même dégradé que votre Drawer
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A1E2B), // Noir/Bleu nuit
              Color(0xFF2D325A), // Bleu ardoise
              Color(0xFF4361EE), // Bleu roi (votre couleur principale)
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Conteneur du logo avec effet "Glow" (lueur)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4361EE).withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/logo.png', // Votre logo
                width: 140, // Taille à ajuster selon les proportions de votre image
                height: 140,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 60),

            // Indicateur de chargement affiné
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5, // Plus fin pour un effet plus élégant
              ),
            ),
            const SizedBox(height: 20),

            // Petit texte de chargement discret
            Text(
              'Connexion sécurisée...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activation_screen.dart';
import 'dashboard_screen.dart';
import 'update_screen.dart';
import '../services/secure_storage_service.dart';

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // 👇 Nouvelle méthode d'initialisation globale
  Future<void> _initializeApp() async {
    // On ajoute un petit délai artificiel pour l'effet Splash Screen
    await Future.delayed(const Duration(milliseconds: 500));

    // 1. On vérifie d'abord les mises à jour
    bool isBlockedByUpdate = await _checkAppVersion();

    // 2. Si une mise à jour obligatoire bloque l'app, on arrête tout ici
    if (isBlockedByUpdate) return;

    // 3. Sinon, on procède à la vérification d'authentification habituelle
    await _checkAuthentication();
  }

  // 👇 Méthode de vérification de version (Corrigée pour le JSON:API)
  Future<bool> _checkAppVersion() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int currentVersionCode = int.parse(packageInfo.buildNumber);

      final response = await http.get(
        Uri.parse('https://admin.sniper-sarl.cloud/api/v1/app/latest-version'),
        headers: {
          'Accept': 'application/vnd.api+json', // 👈 TRÈS IMPORTANT
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded['data'] ?? {};
        final attributes = data['attributes'] ?? {};
        final links = data['links'] ?? {};

        // 👇 On récupère tout dans 'attributes' et 'links'
        final int latestVersionCode = attributes['version_code'] ?? 0;
        final String versionName = attributes['version_name'] ?? '';
        final bool isMandatory = attributes['is_mandatory'] ?? false;
        final String releaseNotes = attributes['release_notes'] ?? '';
        final int sizeBytes = attributes['size_bytes'] ?? 0;
        final String apkUrl = links['download'] ?? '';

        if (latestVersionCode > currentVersionCode && apkUrl.isNotEmpty) {
          if (!mounted) return true;

          if (isMandatory) {
            // Mise à jour OBLIGATOIRE
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => UpdateScreen(
                  updateUrl: apkUrl,
                  releaseNotes: releaseNotes,
                  isMandatory: true,
                  versionName: versionName,
                  sizeBytes: sizeBytes,
                ),
              ),
            );
            return true; // L'application est bloquée
          } else {
            // Mise à jour FACULTATIVE
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UpdateScreen(
                  updateUrl: apkUrl,
                  releaseNotes: releaseNotes,
                  isMandatory: false,
                  versionName: versionName,
                  sizeBytes: sizeBytes,
                ),
              ),
            );
            return false; // L'utilisateur a cliqué sur "Plus tard", on continue
          }
        }
      }
    } catch (e) {
      debugPrint("Erreur lors de la vérification de version: $e");
      // S'il n'y a pas internet ou que le serveur bug, on renvoie "false" pour ne pas bloquer le client
    }
    return false;
  }

  // 👇 Ton code d'authentification inchangé
  Future<void> _checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');
    String? installationId = prefs.getString('installation_id');

    // LA LOGIQUE HYBRIDE DE SURVIE
    if (token == null || token.isEmpty) {
      debugPrint('⚠️ SharedPreferences vides. Tentative de récupération via Keystore...');

      // On vérifie le coffre-fort matériel (qui survit au "Clear Data")
      final secureData = await SecureStorageService.getSecureData();

      if (secureData != null && secureData['token'] != null) {
        // SAUVETAGE RÉUSSI ! Le client a vidé le cache mais le Keystore a tenu bon.
        token = secureData['token'];
        installationId = secureData['installation_id'];

        // On restaure les SharedPreferences pour que le reste de l'app fonctionne vite
        await prefs.setString('auth_token', token!);
        if (installationId != null) {
          await prefs.setString('installation_id', installationId);
        }

        debugPrint('🚀 Session restaurée avec succès depuis le Keystore !');
      } else {
        debugPrint('❌ Keystore vide. Redirection vers l\'activation.');
      }
    }

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // Un token existe -> Go Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      // Aucun token nul part -> Go Activation
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ActivationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A1E2B),
              Color(0xFF2D325A),
              Color(0xFF4361EE),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
                'assets/images/sniper_logo.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 60),

            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 20),

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
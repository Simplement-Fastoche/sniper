import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'dashboard_screen.dart';
import '../services/logger_service.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _contractController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _imeiController = TextEditingController();

  // Variables pour les messages d'erreur sous les champs
  String? _contractError;
  String? _codeError;
  String? _imeiError;

  bool _isLoading = false;
  String? _generalErrorMessage; // Pour les erreurs serveur

  final bool _useMockApi = false;
  final String _apiUrl = 'https://admin.sniper-sarl.cloud/api/v1/auth/activate';

  late final LoggerService _logger;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _logger.init().then((_) {
      _logger.info('ActivationScreen initialisé');
    });

    // Ajout des listeners pour la validation en temps réel
    _contractController.addListener(_validateContract);
    _codeController.addListener(_validateCode);
    _imeiController.addListener(_validateImei);
  }

  // ============ VALIDATIONS EN TEMPS RÉEL ============

  void _validateContract() {
    final value = _contractController.text.trim();
    setState(() {
      if (value.isNotEmpty && value.length < 3) {
        _contractError = 'Le numéro de contrat est trop court';
      } else {
        _contractError = null;
      }
    });
  }

  void _validateCode() {
    final value = _codeController.text.trim();
    setState(() {
      if (value.isNotEmpty && !RegExp(r'^[0-9]{8}$').hasMatch(value)) {
        _codeError = 'Doit contenir exactement 8 chiffres';
      } else {
        _codeError = null;
      }
    });
  }

  void _validateImei() {
    final value = _imeiController.text.trim();
    setState(() {
      if (value.isNotEmpty && !RegExp(r'^[0-9]{4}$').hasMatch(value)) {
        _imeiError = 'Doit contenir exactement 4 chiffres';
      } else {
        _imeiError = null;
      }
    });
  }

  // ============ VALIDATION FINALE ============

  bool _validateFields() {
    setState(() {
      _contractError = null;
      _codeError = null;
      _imeiError = null;
      _generalErrorMessage = null;
    });

    final contract = _contractController.text.trim();
    final code = _codeController.text.trim();
    final imeiSuffix = _imeiController.text.trim();

    bool isValid = true;

    if (contract.isEmpty) {
      setState(() => _contractError = 'Ce champ est requis');
      isValid = false;
    }

    if (code.isEmpty) {
      setState(() => _codeError = 'Ce champ est requis');
      isValid = false;
    } else if (!RegExp(r'^[0-9]{8}$').hasMatch(code)) {
      setState(() => _codeError = 'Doit contenir exactement 8 chiffres');
      isValid = false;
    }

    if (imeiSuffix.isEmpty) {
      setState(() => _imeiError = 'Ce champ est requis');
      isValid = false;
    } else if (!RegExp(r'^[0-9]{4}$').hasMatch(imeiSuffix)) {
      setState(() => _imeiError = 'Doit contenir exactement 4 chiffres');
      isValid = false;
    }

    return isValid;
  }

  // ============ MÉTHODE D'ACTIVATION ============

  Future<String> _getInstallationId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? installationId = prefs.getString('installation_id');
      if (installationId == null) {
        installationId = const Uuid().v4();
        await prefs.setString('installation_id', installationId);
        _logger.info('Nouveau installation_id généré');
      }
      return installationId;
    } catch (e) {
      rethrow;
    }
  }

  // ============ AFFICHAGE DES MESSAGES ============

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5), // 👈 5 secondes
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }



  Future<void> _activateApp() async {
    // 1. Validation des champs
    if (!_validateFields()) {
      _scrollToError();
      return;
    }

    final contract = _contractController.text.trim();
    final code = _codeController.text.trim();
    final imeiSuffix = _imeiController.text.trim();

    setState(() {
      _isLoading = true;
      _generalErrorMessage = null;
    });

    try {
      final installationId = await _getInstallationId();

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.api+json',
        },
        body: jsonEncode({
          "contract_number": contract,
          "activation_code": code,
          "installation_uuid": installationId,
          "imei_suffix": imeiSuffix,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          final data = responseData['data'];
          final attributes = data['attributes'] ?? {};
          final String token = attributes['access_token'] ?? attributes['token'] ?? data['id'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);

          if (mounted) {
            // 👈 SOLUTION 1: Naviguer d'abord, puis afficher le SnackBar
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            );

            // Attendre que la navigation soit terminée
            await Future.delayed(const Duration(milliseconds: 300));

            // Afficher le SnackBar sur le nouveau contexte
            if (mounted) {
              // Récupérer le nouveau contexte
              final dashboardContext = context;
              ScaffoldMessenger.of(dashboardContext).showSnackBar(
                SnackBar(
                  content: const Text('✅ Activation réussie !'),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'OK',
                    textColor: Colors.white,
                    onPressed: () => ScaffoldMessenger.of(dashboardContext).hideCurrentSnackBar(),
                  ),
                ),
              );
            }
          }
        } catch (e) {
          _logger.error('Erreur de décodage', error: e);
          setState(() => _generalErrorMessage = 'Erreur de traitement des données');
          _showSnackBar('Erreur de traitement des données');
        }
      } else {
        // Gestion des erreurs serveur
        try {
          if (response.statusCode == 429) {
            setState(() => _generalErrorMessage = 'Trop de tentatives. Patientez quelques minutes.');
            _showSnackBar('Trop de tentatives. Patientez quelques minutes.');
            return;
          }

          final errorData = jsonDecode(response.body);
          String errorMessage = 'Erreur d\'activation (${response.statusCode})';

          if (errorData.containsKey('errors') && errorData['errors'].isNotEmpty) {
            errorMessage = errorData['errors'][0]['detail'] ?? errorData['errors'][0]['title'] ?? errorMessage;
          } else if (errorData.containsKey('message')) {
            errorMessage = errorData['message'];
          }

          setState(() => _generalErrorMessage = errorMessage);
          _showSnackBar(errorMessage);

        } catch (e) {
          setState(() => _generalErrorMessage = 'Erreur serveur (Code ${response.statusCode})');
          _showSnackBar('Erreur serveur (Code ${response.statusCode})');
        }
      }
    } catch (e) {
      _logger.error('Erreur réseau', error: e);
      setState(() => _generalErrorMessage = 'Erreur de connexion au serveur');
      _showSnackBar('Erreur de connexion. Vérifiez votre connexion internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToError() {
    // Vous pouvez implémenter un scroll vers le champ en erreur
    // avec un ScrollController si nécessaire
  }

  @override
  void dispose() {
    _contractController.dispose();
    _codeController.dispose();
    _imeiController.dispose();
    super.dispose();
  }

  // ============ UI ============

  Widget _buildNeonCard({required Widget child, required Color glowColor}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: glowColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }

  InputDecoration _neonInputDecoration({
    required String labelText,
    required String hintText,
    required IconData icon,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: TextStyle(color: errorText != null ? Colors.red.shade300 : Colors.white60, fontSize: 14),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
      errorText: errorText,
      errorStyle: TextStyle(color: Colors.red.shade300, fontSize: 12),
      errorMaxLines: 2,
      filled: true,
      fillColor: errorText != null
          ? Colors.red.withOpacity(0.08)
          : Colors.white.withOpacity(0.05),
      prefixIcon: Icon(icon, color: errorText != null ? Colors.red.shade300 : const Color(0xFF6C63FF), size: 22),
      counterStyle: const TextStyle(color: Colors.white54),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: errorText != null ? Colors.red.shade300 : Colors.white.withOpacity(0.1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: errorText != null ? Colors.red.shade300 : const Color(0xFF6C63FF),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Activation',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            shadows: [Shadow(color: Color(0xFF6C63FF), blurRadius: 10)],
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculer la hauteur disponible (hauteur totale - AppBar)
          final availableHeight = constraints.maxHeight;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: availableHeight,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Espace flexible pour centrer
                    const Spacer(),

                    // Icône
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.1),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.security, size: 48, color: Color(0xFF6C63FF)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      'Saisissez les informations fournies par l\'agent pour activer ce téléphone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 32),

                    // Message d'erreur général
                    if (_generalErrorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade300, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _generalErrorMessage!,
                                style: TextStyle(color: Colors.red.shade300, fontSize: 14),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _generalErrorMessage = null),
                              child: Icon(Icons.close, color: Colors.red.shade300, size: 18),
                            ),
                          ],
                        ),
                      ),

                    // Formulaire
                    _buildNeonCard(
                      glowColor: const Color(0xFF6C63FF),
                      child: Column(
                        children: [
                          // Champ Contrat
                          TextField(
                            controller: _contractController,
                            keyboardType: TextInputType.text,
                            maxLength: 32,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            decoration: _neonInputDecoration(
                              labelText: 'Numéro de contrat',
                              hintText: 'Ex: SN-2026-...',
                              icon: Icons.description,
                              errorText: _contractError,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Champ Code
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, letterSpacing: 2.0),
                            decoration: _neonInputDecoration(
                              labelText: 'Code d\'activation',
                              hintText: '8 chiffres',
                              icon: Icons.lock_outline,
                              errorText: _codeError,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Champ IMEI
                          TextField(
                            controller: _imeiController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, letterSpacing: 2.0),
                            decoration: _neonInputDecoration(
                              labelText: '4 derniers chiffres IMEI',
                              hintText: 'Ex: 1234',
                              icon: Icons.qr_code,
                              errorText: _imeiError,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Bouton
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _activateApp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: const Color(0xFF6C63FF),
                          disabledBackgroundColor: const Color(0xFF6C63FF).withOpacity(0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                            : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.power_settings_new, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Activer l\'appareil',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Espace flexible pour centrer (en bas)
                    const Spacer(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
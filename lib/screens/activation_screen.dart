import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sniper/screens/update_screen.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../config/app_colors.dart';
import '../services/secure_storage_service.dart';
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
  String? _generalErrorMessage;

  final bool _useMockApi = false;
  late final LoggerService _logger;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _logger.init().then((_) {
      _logger.info('ActivationScreen initialisé');
    });

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
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  Future<void> _activateApp() async {
    if (!_validateFields()) {
      _scrollToError();
      return;
    }

    final contract = _contractController.text.trim().toUpperCase();
    final code = _codeController.text.trim();
    final imeiSuffix = _imeiController.text.trim();

    setState(() {
      _isLoading = true;
      _generalErrorMessage = null;
    });

    try {
      final installationId = await _getInstallationId();

      final response = await http.post(
        Uri.parse(ApiConfig.activateEndpoint),
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
          await SecureStorageService.saveSecureData(token, installationId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '✅ Activation réussie !',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 4),
              ),
            );

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            );
          }
        } catch (e) {
          _logger.error('Erreur de décodage', error: e);
          setState(() => _generalErrorMessage = 'Erreur de traitement des données');
          _showSnackBar('Erreur de traitement des données');
        }
      } else {
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

  void _scrollToError() {}

  @override
  void dispose() {
    _contractController.dispose();
    _codeController.dispose();
    _imeiController.dispose();
    super.dispose();
  }

  // ============ UI ADAPTATIVE (Clair / Sombre) ============

  Widget _buildCard({
    required Widget child,
    required Color cardBg,
    required List<BoxShadow> shadow,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: child,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    required IconData icon,
    String? errorText,
    required Color textHint,
    required Color inputBg,
    required Color inputBorderColor,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: TextStyle(
        color: errorText != null ? AppColors.error : textHint,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: textHint,
        fontSize: 13,
      ),
      errorText: errorText,
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      errorMaxLines: 2,
      filled: true,
      fillColor: inputBg,
      prefixIcon: Icon(
        icon,
        color: errorText != null ? AppColors.error : AppColors.primary,
        size: 22,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: inputBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: errorText != null ? AppColors.error : inputBorderColor,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: errorText != null ? AppColors.error : AppColors.inputFocus,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 👇 DÉTECTION DU MODE SOMBRE ET DÉFINITION DES COULEURS DYNAMIQUES
    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F0F1A) : AppColors.background;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : AppColors.cardBackground;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadow;
    final textPrimary = isDark ? Colors.white : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFFB0B0C0) : AppColors.textSecondary;
    final textHint = isDark ? const Color(0xFF6B7280) : AppColors.textHint;
    final inputBg = isDark ? const Color(0xFF2D2D44) : AppColors.inputBackground;
    final inputBorderColor = isDark ? const Color(0xFF3D3D5C) : AppColors.inputBorder;
    final errorBoxBg = isDark ? AppColors.error.withOpacity(0.15) : AppColors.errorLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Activation',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
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
                    const Spacer(),

                    // Icône avec dégradé
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: AppColors.iconGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          size: 52,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Titre et description
                    Text(
                      'Activation de l\'appareil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Saisissez les informations fournies par l\'agent\npour activer ce téléphone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Message d'erreur général
                    if (_generalErrorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: errorBoxBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _generalErrorMessage!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _generalErrorMessage = null),
                              child: const Icon(
                                Icons.close,
                                color: AppColors.error,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Formulaire
                    _buildCard(
                      cardBg: cardBg,
                      shadow: shadow,
                      child: Column(
                        children: [
                          // Champ Contrat
                          TextField(
                            controller: _contractController,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              TextInputFormatter.withFunction((oldValue, newValue) {
                                return newValue.copyWith(text: newValue.text.toUpperCase());
                              }),
                            ],
                            maxLength: 32,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                            decoration: _buildInputDecoration(
                              labelText: 'Numéro de contrat',
                              hintText: 'Ex: SN-2026-001',
                              icon: Icons.description_outlined,
                              errorText: _contractError,
                              textHint: textHint,
                              inputBg: inputBg,
                              inputBorderColor: inputBorderColor,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Champ Code
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              letterSpacing: 2.0,
                            ),
                            decoration: _buildInputDecoration(
                              labelText: 'Code d\'activation',
                              hintText: '8 chiffres',
                              icon: Icons.lock_outline_rounded,
                              errorText: _codeError,
                              textHint: textHint,
                              inputBg: inputBg,
                              inputBorderColor: inputBorderColor,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Champ IMEI
                          TextField(
                            controller: _imeiController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                              letterSpacing: 2.0,
                            ),
                            decoration: _buildInputDecoration(
                              labelText: '4 derniers chiffres IMEI',
                              hintText: 'Ex: 1234',
                              icon: Icons.qr_code_scanner_rounded,
                              errorText: _imeiError,
                              textHint: textHint,
                              inputBg: inputBg,
                              inputBorderColor: inputBorderColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Bouton d'activation avec dégradé
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _activateApp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                            : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Activer l\'appareil',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Note de sécurité
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: textHint,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Connexion sécurisée',
                          style: TextStyle(
                            fontSize: 12,
                            color: textHint,
                          ),
                        ),
                      ],
                    ),

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



  // 👇 Méthode de vérification de version adaptée à ton API
  Future<bool> _checkAppVersion() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int currentVersionCode = int.parse(packageInfo.buildNumber);

      final response = await http.get(
        Uri.parse('https://admin.sniper-sarl.cloud/api/v1/app/latest-version'),
        headers: {
          'Accept': 'application/vnd.api+json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded['data'] ?? {};
        final attributes = data['attributes'] ?? {};
        final links = data['links'] ?? {};

        final int latestVersionCode = attributes['version_code'] ?? 0;
        final String versionName = attributes['version_name'] ?? '';
        final bool isMandatory = attributes['is_mandatory'] ?? false;
        final String releaseNotes = attributes['release_notes'] ?? '';
        final int sizeBytes = attributes['size_bytes'] ?? 0;
        final String downloadUrl = links['download'] ?? '';

        // Comparaison : Si la version du serveur est supérieure à celle installée
        if (latestVersionCode > currentVersionCode && downloadUrl.isNotEmpty) {
          if (!mounted) return true;

          if (isMandatory) {
            // Mise à jour OBLIGATOIRE : remplace l'écran actuel
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => UpdateScreen(
                  updateUrl: downloadUrl,
                  releaseNotes: releaseNotes,
                  isMandatory: true,
                  versionName: versionName,
                  sizeBytes: sizeBytes,
                ),
              ),
            );
            return true; // Bloque le reste du chargement
          } else {
            // Mise à jour FACULTATIVE : l'utilisateur peut cliquer "Plus tard"
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UpdateScreen(
                  updateUrl: downloadUrl,
                  releaseNotes: releaseNotes,
                  isMandatory: false,
                  versionName: versionName,
                  sizeBytes: sizeBytes,
                ),
              ),
            );
            return false; // L'utilisateur continue vers le Dashboard/Activation
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Erreur lors de la vérification de version: $e");
      // En cas d'erreur réseau, on ne bloque pas le client
    }
    return false;
  }


}
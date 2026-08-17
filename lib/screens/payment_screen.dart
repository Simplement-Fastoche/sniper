import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../config/app_colors.dart';
import '../services/logger_service.dart';
import '../services/theme_service.dart';
import '../widgets/ErrorPopupWidget.dart';
import '../config/api_config.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedCurrency = 'USD';

  bool _isLoading = false;
  bool _isConfirming = false;

  String? _errorMessage;
  // 👇 NOUVELLES VARIABLES POUR LES ERREURS CIBLÉES
  String? _phoneError;
  String? _amountError;

  Map<String, dynamic>? _quoteData;

  late final LoggerService _logger;
  late final ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _themeService = ThemeService();
    _logger.init().then((_) {
      _logger.info('PaymentScreen initialisé');
    });

    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');
      if (token == null) return;

      final response = await http.get(
        Uri.parse(ApiConfig.meEndpoint),
        headers: {
          'Accept': 'application/vnd.api+json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final attributes = decoded['data']['attributes'];
        final profile = attributes['profile'] ?? {};

        final phones = profile['phones'] as List<dynamic>? ?? [];
        String primaryPhone = '';
        for (var phone in phones) {
          if (phone['primary'] == true || phone['primary'] == 1) {
            primaryPhone = phone['number'] ?? '';
            break;
          }
        }
        if (primaryPhone.isEmpty && phones.isNotEmpty) {
          primaryPhone = phones[0]['number'] ?? '';
        }

        if (mounted) {
          setState(() {
            if (primaryPhone.isNotEmpty) {
              _phoneController.text = primaryPhone;
            }
          });
        }
      }
    } catch (e) {
      _logger.warning("Erreur chargement données initiales paiement: $e");
    }
  }

  void _showError(String title, String message, {Map<String, dynamic>? details}) {
    if (mounted) {
      ErrorPopupWidget.showErrorDialog(
        context,
        title: title,
        message: message,
        details: details,
        showAllLogs: false,
      );
    }
  }

  Future<void> _fetchQuote() async {
    final amountText = _amountController.text.trim();
    final phone = _phoneController.text.trim();

    // 👇 RÉINITIALISATION DES ERREURS AVANT VÉRIFICATION
    setState(() {
      _phoneError = null;
      _amountError = null;
      _errorMessage = null;
    });

    bool hasError = false;

    // 👇 VÉRIFICATIONS CIBLÉES
    if (phone.isEmpty) {
      setState(() => _phoneError = "Veuillez entrer un numéro de téléphone.");
      hasError = true;
    }

    if (amountText.isEmpty) {
      setState(() => _amountError = "Veuillez entrer un montant.");
      hasError = true;
    }

    if (hasError) return;

    final double? parsedAmount = double.tryParse(amountText);

    if (parsedAmount == null) {
      setState(() => _amountError = "Le montant saisi est invalide.");
      return;
    }
    if (_selectedCurrency == 'USD' && parsedAmount < 1.00) {
      setState(() => _amountError = "Le montant minimum est de 1.00 USD.");
      return;
    }
    if (_selectedCurrency == 'CDF' && parsedAmount < 500.00) {
      setState(() => _amountError = "Le montant minimum est de 500.00 CDF.");
      return;
    }

    // S'il n'y a pas d'erreur, on lance le chargement
    setState(() {
      _isLoading = true;
      _quoteData = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');
      final String correlationId = const Uuid().v4();

      _logger.info('Demande de devis', data: {'amount': parsedAmount, 'currency': _selectedCurrency, 'phone': phone});

      final response = await http.post(
        Uri.parse(ApiConfig.quoteEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.api+json',
          'Accept-Language': 'fr',
          'X-Correlation-ID': correlationId,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          "currency": _selectedCurrency,
          "amount": parsedAmount.toStringAsFixed(2),
        }),
      );

      _logger.info('Réponse Devis API', data: {
        'status_code': response.statusCode,
        'body': response.body,
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded['data'];
        final attrs = data['attributes'];

        setState(() {
          _quoteData = {
            "quote_id": data['id'],
            "amount_cdf": _selectedCurrency == 'CDF' ? attrs['amount'] : (attrs['amount'] ?? amountText),
            "amount_usd": attrs['credited_usd']?.toString() ?? '0.00',
            "currency": _selectedCurrency,
            "payer_phone": phone,
          };
          _isLoading = false;
        });
      } else if (response.statusCode == 429) {
        setState(() {
          _errorMessage = "Trop de tentatives. Veuillez patienter un instant.";
          _isLoading = false;
        });
      } else {
        Map<String, dynamic> errorDetails = {};
        try {
          final errorData = jsonDecode(response.body);
          if (errorData.containsKey('errors') && errorData['errors'].isNotEmpty) {
            errorDetails = {'detail': errorData['errors'][0]['detail'] ?? errorData['errors'][0]['title']};
            setState(() => _errorMessage = errorDetails['detail']);
          } else {
            setState(() => _errorMessage = "Erreur lors de la création du devis.");
          }
        } catch (_) {}

        _logger.warning('Erreur génération devis', data: {'body': response.body});
        _isLoading = false;
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Devis', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = "Erreur de connexion au serveur.";
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmPayment() async {
    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');
      final String phone = _phoneController.text.trim();

      final String idempotencyKey = const Uuid().v4();
      final String correlationId = const Uuid().v4();

      final payload = {
        "quote_id": _quoteData!['quote_id'],
        "payer_phone": phone.startsWith('+') ? phone : '+243${phone.substring(phone.startsWith('0') ? 1 : 0)}',
      };

      _logger.info('Lancement du paiement', data: payload);

      final response = await http.post(
        Uri.parse(ApiConfig.paymentsEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.api+json',
          'Accept-Language': 'fr',
          'X-Correlation-ID': correlationId,
          'Idempotency-Key': idempotencyKey,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      _logger.info('Réponse Paiement API', data: {
        'status_code': response.statusCode,
        'body': response.body,
      });

      if (response.statusCode == 202 || response.statusCode == 201 || response.statusCode == 200) {

        if (mounted) {
          setState(() {
            _quoteData = null;
            _amountController.clear();
          });

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: _themeService.isDarkMode ? const Color(0xFF1E1E2E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.all(24),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFED8936).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phonelink_ring, size: 48, color: Color(0xFFED8936)),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Paiement en cours",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _themeService.isDarkMode ? Colors.white : const Color(0xFF1A202C),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Veuillez consulter votre téléphone et entrer votre code PIN Mobile Money pour valider la transaction.\n\nLe traitement peut prendre jusqu'à 5 minutes. Vous pourrez vérifier le statut final dans l'historique.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _themeService.isDarkMode ? const Color(0xFFB0B0C0) : const Color(0xFF4A5568),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: const Color(0xFF7CB342),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "J'ai compris",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  )
                ],
              ),
            ),
          );
        }
      } else if (response.statusCode == 429) {
        setState(() { _errorMessage = "Système surchargé. Veuillez réessayer."; });
      } else {
        Map<String, dynamic> errorDetails = {};
        try {
          final errorData = jsonDecode(response.body);
          if (errorData.containsKey('errors') && errorData['errors'].isNotEmpty) {
            errorDetails = {'detail': errorData['errors'][0]['detail']};
          }
        } catch (_) {}

        _logger.warning('Paiement refusé par le serveur', data: {'body': response.body});
        setState(() { _errorMessage = "Le paiement n'a pas pu être lancé."; });
        _showError('Échec du paiement', 'Vérifiez le numéro et votre solde.', details: errorDetails);
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Paiement', error: e, stackTrace: stackTrace);
      setState(() { _errorMessage = "Erreur de réseau."; });
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildCard({required Widget child, required Color cardBg, required List<BoxShadow> shadow}) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  // 👇 MISE À JOUR : Ajout du paramètre `errorText`
  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    required IconData icon,
    required Color textPrimary,
    required Color textHint,
    required Color inputBorder,
    required Color inputFocus,
    required Color inputBackground,
    String? errorText, // NOUVEAU
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: TextStyle(
        // Le label devient rouge s'il y a une erreur
          color: errorText != null ? AppColors.error : textHint,
          fontSize: 14
      ),
      hintStyle: TextStyle(color: textHint.withOpacity(0.5), fontSize: 13),
      errorText: errorText, // Affichage ciblé de l'erreur
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: inputBackground,
      prefixIcon: Icon(
          icon,
          // L'icône devient rouge s'il y a une erreur
          color: errorText != null ? AppColors.error : inputFocus,
          size: 22
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
            color: errorText != null ? AppColors.error : inputBorder
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
            color: errorText != null ? AppColors.error : inputFocus,
            width: 2
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeService.isDarkMode;
    final bgColor = isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFFFFFFF);
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadow;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A202C);
    final textSecondary = isDark ? const Color(0xFFB0B0C0) : const Color(0xFF4A5568);
    final textHint = isDark ? const Color(0xFF6B7280) : const Color(0xFFA0AEC0);
    final inputBorder = isDark ? const Color(0xFF3D3D5C) : const Color(0xFFCBD5E1);
    final inputFocus = const Color(0xFF7CB342);
    final inputBackground = isDark ? const Color(0xFF2D2D44) : const Color(0xFFFFFFFF);
    final errorColor = const Color(0xFFE53E3E);

    return Container(
      color: bgColor,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputForm(
                  isDark: isDark,
                  cardBg: cardBg,
                  shadow: shadow,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textHint: textHint,
                  inputBorder: inputBorder,
                  inputFocus: inputFocus,
                  inputBackground: inputBackground,
                  errorColor: errorColor,
                ),
                const SizedBox(height: 24),

                if (_quoteData == null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7CB342).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _fetchQuote,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7CB342),
                        disabledBackgroundColor: const Color(0xFF7CB342).withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                          Icon(Icons.search, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Prévisualiser le paiement',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: errorColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (_quoteData != null) ...[
                  _buildQuoteCard(
                    isDark: isDark,
                    cardBg: cardBg,
                    shadow: shadow,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    textHint: textHint,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38A169).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isConfirming ? null : _confirmPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38A169),
                        disabledBackgroundColor: const Color(0xFF38A169).withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isConfirming
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
                          Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Confirmer et Payer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isConfirming ? null : () => setState(() => _quoteData = null),
                    child: Text(
                      'Annuler et modifier',
                      style: TextStyle(
                        color: textHint,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputForm({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color inputFocus,
    required Color inputBackground,
    required Color errorColor,
  }) {
    return _buildCard(
      cardBg: cardBg,
      shadow: shadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7CB342).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.payment,
                  color: Color(0xFF7CB342),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Nouveau Paiement',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: _quoteData == null,
            style: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
            // 👇 On passe _phoneError à la décoration
            decoration: _buildInputDecoration(
              labelText: 'Numéro Mobile Money',
              hintText: 'Ex: +243812345678',
              icon: Icons.phone_android,
              textPrimary: textPrimary,
              textHint: textHint,
              inputBorder: inputBorder,
              inputFocus: inputFocus,
              inputBackground: inputBackground,
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _quoteData != null ? null : () => setState(() => _selectedCurrency = 'CDF'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCurrency == 'CDF'
                          ? const Color(0xFF7CB342).withOpacity(0.1)
                          : Colors.transparent,
                      border: Border.all(
                        color: _selectedCurrency == 'CDF'
                            ? const Color(0xFF7CB342)
                            : inputBorder,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'CDF',
                        style: TextStyle(
                          color: _selectedCurrency == 'CDF'
                              ? const Color(0xFF7CB342)
                              : textHint,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _quoteData != null ? null : () => setState(() => _selectedCurrency = 'USD'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCurrency == 'USD'
                          ? const Color(0xFF7CB342).withOpacity(0.1)
                          : Colors.transparent,
                      border: Border.all(
                        color: _selectedCurrency == 'USD'
                            ? const Color(0xFF7CB342)
                            : inputBorder,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'USD',
                        style: TextStyle(
                          color: _selectedCurrency == 'USD'
                              ? const Color(0xFF7CB342)
                              : textHint,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: _quoteData == null,
            style: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
            // 👇 On passe _amountError à la décoration
            decoration: _buildInputDecoration(
              labelText: 'Montant',
              hintText: 'Ex: 85000',
              icon: Icons.account_balance_wallet,
              textPrimary: textPrimary,
              textHint: textHint,
              inputBorder: inputBorder,
              inputFocus: inputFocus,
              inputBackground: inputBackground,
              errorText: _amountError,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
  }) {
    final double amountCdf = double.tryParse(_quoteData!['amount_cdf'].toString()) ?? 0.0;
    final double amountUsd = double.tryParse(_quoteData!['amount_usd'].toString()) ?? 0.0;
    final String currency = _quoteData!['currency'].toString();
    final String payerPhone = _quoteData!['payer_phone']?.toString() ?? '-';

    final double exchangeRate = (amountUsd > 0 && amountCdf > 0) ? (amountCdf / amountUsd) : 0.0;

    final formatCdf = NumberFormat.currency(locale: 'fr_FR', symbol: 'CDF', decimalDigits: 2);
    final formatUsd = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    final bgColor = isDark ? const Color(0xFF2D2D44) : const Color(0xFFF1F5F9);

    return _buildCard(
      cardBg: cardBg,
      shadow: shadow,
      child: Column(
        children: [
          Text(
            'RÉSUMÉ DE LA TRANSACTION',
            style: TextStyle(
              fontSize: 12,
              color: textHint,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Montant payé :',
                style: TextStyle(fontSize: 16, color: textSecondary),
              ),
              Text(
                currency == 'CDF' ? formatCdf.format(amountCdf) : formatUsd.format(amountUsd),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
            ],
          ),

          if (currency == 'CDF') ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Équivalent en USD :',
                  style: TextStyle(fontSize: 14, color: textHint),
                ),
                Text(
                  formatUsd.format(amountUsd),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Container(
              height: 1,
              color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFCBD5E1),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7CB342).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    size: 16,
                    color: Color(0xFF7CB342),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Compte mobile',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  payerPhone,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          if (currency == 'CDF' && exchangeRate > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFCBD5E1).withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.currency_exchange,
                      size: 16,
                      color: Color(0xFF7CB342),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Taux du contrat',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '1 USD = ${exchangeRate.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }
}
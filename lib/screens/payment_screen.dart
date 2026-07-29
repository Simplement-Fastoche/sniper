import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../services/logger_service.dart';
import '../widgets/ErrorPopupWidget.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedCurrency = 'CDF'; // NOUVEAU : Gestion de la devise

  bool _isLoading = false;
  bool _isConfirming = false;
  String? _errorMessage;
  Map<String, dynamic>? _quoteData;

  // NOUVELLES URLs DE L'API (v1/device/...)
  final String _quoteUrl = 'https://api.sniper-sarl.cloud/v1/device/payment-quotes';
  final String _paymentUrl = 'https://api.sniper-sarl.cloud/v1/device/payments';

  late final LoggerService _logger;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _logger.init().then((_) {
      _logger.info('PaymentScreen initialisé');
    });
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

  String _detectOperator(String phone) {
    final cleanPhone = phone.replaceAll(' ', '');
    if (cleanPhone.startsWith('081') || cleanPhone.startsWith('082') || cleanPhone.startsWith('083')) return 'vodacom';
    if (cleanPhone.startsWith('099') || cleanPhone.startsWith('097')) return 'airtel';
    if (cleanPhone.startsWith('089') || cleanPhone.startsWith('084') || cleanPhone.startsWith('085')) return 'orange';
    if (cleanPhone.startsWith('090')) return 'africell';
    return 'inconnu';
  }

  // --- ÉTAPE 1 : GÉNÉRATION DU DEVIS ---
  Future<void> _fetchQuote() async {
    final amountText = _amountController.text.trim();
    final phone = _phoneController.text.trim();

    if (amountText.isEmpty || phone.isEmpty) {
      setState(() => _errorMessage = "Veuillez remplir le numéro et le montant.");
      return;
    }

    final double? parsedAmount = double.tryParse(amountText);
    if (parsedAmount == null || parsedAmount < 0.01) {
      setState(() => _errorMessage = "Montant invalide.");
      return;
    }

    final detectedOperator = _detectOperator(phone);
    if (detectedOperator == 'inconnu') {
      setState(() => _errorMessage = "Préfixe réseau non reconnu.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _quoteData = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      _logger.info('Demande de devis', data: {'amount': parsedAmount, 'currency': _selectedCurrency, 'phone': phone});

      final response = await http.post(
        Uri.parse(_quoteUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.api+json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          "currency": _selectedCurrency, // Utilisation de la devise sélectionnée
          "amount": parsedAmount,
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
            "amount_cdf": attrs['amount']?.toString() ?? amountText,
            "amount_usd": attrs['credited_usd']?.toString() ?? '0.00',
            "currency": _selectedCurrency,
            "operator": detectedOperator,
          };
          _isLoading = false;
        });
      } else if (response.statusCode == 429) {
        setState(() {
          _errorMessage = "Trop de tentatives. Veuillez patienter un instant.";
          _isLoading = false;
        });
      } else {
        _logger.warning('Erreur génération devis', data: {'body': response.body});
        setState(() {
          _errorMessage = "Erreur lors de la création du devis.";
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Devis', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = "Erreur de connexion au serveur.";
        _isLoading = false;
      });
    }
  }

  // --- ÉTAPE 2 : CONFIRMATION DU PAIEMENT ---
  Future<void> _confirmPayment() async {
    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');
      final String phone = _phoneController.text.trim();
      final String amountText = _amountController.text.trim();
      final String idempotencyKey = "android-payment-${const Uuid().v4()}";

      // NOUVEAU PAYLOAD SELON LA NOUVELLE DOCUMENTATION
      final payload = {
        "type": "collection",
        "amount": amountText,
        "currency": _selectedCurrency,
        "mobile_money": phone,
        "reason": "Paiement mensualité téléphone",
        "idempotency_key": idempotencyKey
      };

      _logger.info('Lancement du paiement', data: payload);

      final response = await http.post(
        Uri.parse(_paymentUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/vnd.api+json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      _logger.info('Réponse Paiement API', data: {
        'status_code': response.statusCode,
        'body': response.body,
      });

      if (response.statusCode == 202 || response.statusCode == 201 || response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final paymentId = decoded['data']['id'];

        if (mounted) {
          final finalStatus = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (context) => PaymentTrackingDialog(
              paymentId: paymentId,
              token: token!,
              logger: _logger,
            ),
          );

          if (finalStatus == 'completed' || finalStatus == 'paid' || finalStatus == 'successful') {
            setState(() {
              _quoteData = null;
              _amountController.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Paiement validé avec succès !'), backgroundColor: Colors.green),
            );
          }
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

  // =========================================================
  // DESIGN NÉON : HELPERS
  // =========================================================

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
        border: Border.all(
          color: glowColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.2),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  InputDecoration _neonInputDecoration({required String labelText, required String hintText, required IconData icon}) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 14),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 22),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CORRECTION : Container + Stack pour corriger le problème du fond blanc
    return Container(
      color: const Color(0xFF0A0A1A), // Fond sombre Néon forcé
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInputForm(),
                const SizedBox(height: 24),

                if (_quoteData == null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _fetchQuote,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        disabledBackgroundColor: const Color(0xFF6C63FF).withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isLoading
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Prévisualiser le paiement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ),

                if (_quoteData != null) ...[
                  _buildQuoteCard(),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isConfirming ? null : _confirmPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50), // Vert Néon
                        disabledBackgroundColor: const Color(0xFF4CAF50).withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isConfirming
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Confirmer et Payer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isConfirming ? null : () => setState(() => _quoteData = null),
                    child: const Text('Annuler et modifier', style: TextStyle(color: Colors.white54, fontSize: 14)),
                  ),
                ]
              ],
            ),
          ),

        ],
      ),
    );
  }

  // --- WIDGETS DE DESIGN ---
  Widget _buildInputForm() {
    return _buildNeonCard(
      glowColor: const Color(0xFF6C63FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payment, color: Color(0xFF6C63FF), size: 24),
              SizedBox(width: 10),
              Text(
                'Nouveau Paiement',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0xFF6C63FF), blurRadius: 8)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: _quoteData == null,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            decoration: _neonInputDecoration(
              labelText: 'Numéro Mobile Money',
              hintText: 'Ex: 0812345678',
              icon: Icons.phone_android,
            ),
          ),
          const SizedBox(height: 16),

          // SÉLECTEUR DE DEVISE (NÉON TOGGLE)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _quoteData != null ? null : () => setState(() => _selectedCurrency = 'CDF'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCurrency == 'CDF' ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.transparent,
                      border: Border.all(color: _selectedCurrency == 'CDF' ? const Color(0xFF6C63FF) : Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('CDF', style: TextStyle(
                          color: _selectedCurrency == 'CDF' ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.bold
                      )),
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
                      color: _selectedCurrency == 'USD' ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.transparent,
                      border: Border.all(color: _selectedCurrency == 'USD' ? const Color(0xFF6C63FF) : Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('USD', style: TextStyle(
                          color: _selectedCurrency == 'USD' ? Colors.white : Colors.white54,
                          fontWeight: FontWeight.bold
                      )),
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            decoration: _neonInputDecoration(
              labelText: 'Montant',
              hintText: 'Ex: 85000',
              icon: Icons.account_balance_wallet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard() {
    final double amountCdf = double.tryParse(_quoteData!['amount_cdf']) ?? 0.0;
    final double amountUsd = double.tryParse(_quoteData!['amount_usd']) ?? 0.0;
    final String operatorCode = _quoteData!['operator'].toString();
    final String currency = _quoteData!['currency'].toString();

    // Le taux n'a de sens que s'il y a conversion
    final double exchangeRate = (amountUsd > 0) ? (amountCdf / amountUsd) : 0.0;

    String operatorName = operatorCode.toUpperCase();

    Color operatorColor = const Color(0xFF6C63FF);
    if (operatorCode == 'vodacom') operatorColor = const Color(0xFFFF4B4B);
    if (operatorCode == 'airtel') operatorColor = const Color(0xFFFF1744);
    if (operatorCode == 'orange') operatorColor = const Color(0xFFFF9800);
    if (operatorCode == 'africell') operatorColor = const Color(0xFF9C27B0);

    final formatCdf = NumberFormat.currency(locale: 'fr_FR', symbol: 'CDF', decimalDigits: 2);
    final formatUsd = NumberFormat.currency(locale: 'en_US', symbol: '\$');

    return _buildNeonCard(
      glowColor: operatorColor,
      child: Column(
        children: [
          const Text('RÉSUMÉ DE LA TRANSACTION', style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Montant payé :', style: TextStyle(fontSize: 16, color: Colors.white70)),
              Text(
                currency == 'CDF' ? formatCdf.format(amountCdf) : formatUsd.format(amountUsd),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: operatorColor,
                  shadows: [Shadow(color: operatorColor.withOpacity(0.6), blurRadius: 8)],
                ),
              )
            ],
          ),
          const SizedBox(height: 10),

          // Si l'utilisateur paie en CDF, on lui montre l'équivalent en USD (et inversement)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Équivalent :', style: TextStyle(fontSize: 14, color: Colors.white54)),
              Text(
                  currency == 'CDF' ? formatUsd.format(amountUsd) : formatCdf.format(amountCdf),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
              )
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: operatorColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cell_tower, size: 16, color: operatorColor),
              ),
              const SizedBox(width: 12),
              const Text('Réseau', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const Spacer(),
              Text(
                operatorName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: operatorColor,
                  fontSize: 14,
                  shadows: [Shadow(color: operatorColor.withOpacity(0.5), blurRadius: 5)],
                ),
              )
            ],
          ),
          if (exchangeRate > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                  child: const Icon(Icons.currency_exchange, size: 16, color: Colors.white60),
                ),
                const SizedBox(width: 12),
                const Text('Taux estimé', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const Spacer(),
                Text('1 USD = ${exchangeRate.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14))
              ],
            )
          ]
        ],
      ),
    );
  }
}

// ============================================================================
// DIALOGUE DE SUIVI (POLLING) - ADAPTÉ AU MODE SOMBRE
// ============================================================================

class PaymentTrackingDialog extends StatefulWidget {
  final String paymentId;
  final String token;
  final LoggerService logger;

  const PaymentTrackingDialog({
    super.key,
    required this.paymentId,
    required this.token,
    required this.logger,
  });

  @override
  State<PaymentTrackingDialog> createState() => _PaymentTrackingDialogState();
}

class _PaymentTrackingDialogState extends State<PaymentTrackingDialog> {
  Timer? _pollingTimer;
  String _status = 'pending';
  int _attempts = 0;
  final int _maxAttempts = 24;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      _attempts++;
      if (_attempts >= _maxAttempts) {
        _stopTimer();
        if (mounted) setState(() => _status = 'expired');
        return;
      }
      await _checkPaymentStatus();
    });
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final url = Uri.parse('https://api.sniper-sarl.cloud/v1/device/payments/${widget.paymentId}');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.api+json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (response.statusCode == 429) {
        widget.logger.warning('Polling Rate limit (429), tentative ignorée.');
        return;
      }

      if (response.statusCode == 200 && mounted) {
        final decoded = jsonDecode(response.body);
        final attrs = decoded['data']['attributes'];

        // CORRECTION IMPORTANTE : L'API utilise 'state' et non 'status' maintenant
        final newStatus = attrs['state']?.toString().toLowerCase().trim() ?? 'pending';

        widget.logger.info('Polling Payment #${widget.paymentId}', data: {'state': newStatus});

        setState(() { _status = newStatus; });

        final isSuccess = ['completed', 'success', 'successful', 'paid', 'approved', 'done'].contains(_status);
        final isFailed = ['failed', 'reversed', 'cancelled', 'error'].contains(_status);

        if (isSuccess || isFailed || _status == 'expired') {
          _stopTimer();
          if (isSuccess) setState(() => _status = 'completed');
          if (isFailed) setState(() => _status = 'failed');
        }
      }
    } catch (e) {
      widget.logger.warning("Erreur de polling: $e");
    }
  }

  void _stopTimer() {
    if (_pollingTimer != null && _pollingTimer!.isActive) {
      _pollingTimer!.cancel();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E), // Fond sombre pour le popup
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      contentPadding: const EdgeInsets.all(32),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusIcon(),
          const SizedBox(height: 24),
          _buildStatusText(),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _status == 'pending' || _status == 'processing' ? null : () => Navigator.pop(context, _status),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: _status == 'completed' ? const Color(0xFF4CAF50) : const Color(0xFF6C63FF),
              disabledBackgroundColor: const Color(0xFF6C63FF).withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              _status == 'pending' || _status == 'processing' ? 'Validation...' : 'Fermer',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (['completed'].contains(_status)) return const Icon(Icons.check_circle, size: 80, color: Color(0xFF4CAF50));
    if (['failed'].contains(_status)) return const Icon(Icons.cancel, size: 80, color: Color(0xFFFF6B6B));
    if (_status == 'expired') return const Icon(Icons.timer_off, size: 80, color: Color(0xFFFF9800));

    return const Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(height: 80, width: 80, child: CircularProgressIndicator(strokeWidth: 4, color: Color(0xFF6C63FF))),
        Icon(Icons.phonelink_ring, size: 36, color: Color(0xFF6C63FF)),
      ],
    );
  }

  Widget _buildStatusText() {
    if (['completed'].contains(_status)) {
      return const Text('Paiement réussi !', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)));
    }
    if (['failed'].contains(_status)) {
      return const Text('Le paiement a échoué.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Color(0xFFFF6B6B)));
    }
    if (_status == 'expired') {
      return const Text('Délai expiré.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Color(0xFFFF9800)));
    }

    return const Column(
      children: [
        Text('Consultez votre téléphone', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        SizedBox(height: 12),
        Text('Entrez votre code PIN Mobile Money pour valider la transaction.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.4)),
      ],
    );
  }
}
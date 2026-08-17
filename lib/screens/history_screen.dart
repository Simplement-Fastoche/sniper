import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../services/logger_service.dart';
import '../services/theme_service.dart';
import '../widgets/ErrorPopupWidget.dart';
import '../config/api_config.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _hasMoreData = true;
  bool _isFetchingMore = false;

  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _payments = [];

  late final LoggerService _logger;
  late final ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _themeService = ThemeService();
    _logger.init().then((_) {
      _logger.info('HistoryScreen initialisé');
    });

    _fetchHistory(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasMoreData) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    setState(() {
      _isFetchingMore = true;
      _currentPage++;
    });
    await _fetchHistory(refresh: false);
  }

  Future<void> _fetchHistory({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMoreData = true;
      if (mounted) {
        setState(() {
          if (_payments.isEmpty) _isLoading = true;
          _errorMessage = null;
        });
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      if (token == null) {
        if (mounted) setState(() { _errorMessage = "Session expirée."; _isLoading = false; });
        return;
      }

      final url = Uri.parse('${ApiConfig.paymentsEndpoint}?page=$_currentPage');

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.api+json, application/json',
          'Authorization': 'Bearer $token',
        },
      );

      _logger.info('=== API PAYMENTS (Page $_currentPage) ===', data: {
        'status_code': response.statusCode,
        'body': response.body,
      });

      if (response.statusCode == 200) {
        final decodedData = jsonDecode(response.body);
        final List<dynamic> rawItems = decodedData['data'] ?? [];
        final meta = decodedData['meta'];

        final newItems = rawItems.map((item) {
          final attrs = item['attributes'] ?? {};
          return {
            "reference": attrs['provider_reference'] ?? item['id'],
            "currency": attrs['currency']?.toString().toUpperCase() ?? 'USD',
            "amount_raw": attrs['amount']?.toString() ?? '0',
            "amount_usd": attrs['credited_usd']?.toString() ?? '0.00',
            "network": attrs['network']?.toString() ?? 'inconnu',
            "status": attrs['status']?.toString() ?? 'pending',
            "status_label": attrs['status_label']?.toString(),
            "date": attrs['completed_at'] ?? attrs['initiated_at'] ?? DateTime.now().toIso8601String(),
          };
        }).toList();

        if (mounted) {
          setState(() {
            if (refresh) {
              _payments = newItems;
            } else {
              _payments.addAll(newItems);
            }

            if (meta != null && meta['current_page'] != null && meta['last_page'] != null) {
              _hasMoreData = meta['current_page'] < meta['last_page'];
            } else {
              _hasMoreData = false;
            }

            _isLoading = false;
            _isFetchingMore = false;
          });
        }
      } else if (response.statusCode == 429) {
        _logger.warning('Rate limit atteint sur l\'historique (429)');
        if (mounted) {
          setState(() {
            if (refresh && _payments.isEmpty) _errorMessage = "Trop de requêtes. Veuillez patienter.";
            _isLoading = false;
            _isFetchingMore = false;
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.warning('Accès refusé', data: {'status': response.statusCode});
        if (mounted) {
          setState(() {
            if (refresh) _errorMessage = "Session expirée ou accès refusé.";
            _isLoading = false;
            _isFetchingMore = false;
          });
        }
      } else {
        _logger.warning('Erreur API Payments', data: {'status': response.statusCode});
        if (mounted) {
          setState(() {
            if (refresh && _payments.isEmpty) _errorMessage = "Impossible de charger l'historique.";
            _isLoading = false;
            _isFetchingMore = false;
          });
        }
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Payments', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          if (refresh && _payments.isEmpty) _errorMessage = "Erreur de réseau.";
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  void _showError(String title, String message, {VoidCallback? onRetry}) {
    if (mounted) {
      ErrorPopupWidget.showErrorDialog(
        context,
        title: title,
        message: message,
        showAllLogs: false,
        onRetry: onRetry,
      );
    }
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
    final errorColor = const Color(0xFFE53E3E);

    return Container(
      color: bgColor,
      child: _buildBody(
        isDark: isDark,
        cardBg: cardBg,
        shadow: shadow,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textHint: textHint,
        inputBorder: inputBorder,
        errorColor: errorColor,
      ),
    );
  }

  Widget _buildBody({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color errorColor,
  }) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF7CB342),
          strokeWidth: 3,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: textPrimary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchHistory(refresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7CB342),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text('Réessayer'),
            )
          ],
        ),
      );
    }

    if (_payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: textHint,
            ),
            const SizedBox(height: 16),
            Text(
              "Aucun paiement récent.",
              style: TextStyle(
                color: textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchHistory(refresh: true),
      color: const Color(0xFF7CB342),
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _payments.length + (_isFetchingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _payments.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF7CB342),
                  strokeWidth: 2.5,
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildPaymentCard(
              payment: _payments[index],
              isDark: isDark,
              cardBg: cardBg,
              shadow: shadow,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textHint: textHint,
              inputBorder: inputBorder,
            ),
          );
        },
      ),
    );
  }

  // ==================== CARTE PAIEMENT STYLE ÉLÉGANT ====================

  Widget _buildPaymentCard({
    required Map<String, dynamic> payment,
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
  }) {
    final DateTime date = (DateTime.tryParse(payment['date']) ?? DateTime.now()).toLocal();
    final String currency = payment['currency'] ?? 'USD';
    final double amountRaw = double.tryParse(payment['amount_raw']) ?? 0.0;
    final double amountUsd = double.tryParse(payment['amount_usd']) ?? 0.0;
    final String operator = payment['network'].toString().toLowerCase();

    final String status = payment['status'].toString().toLowerCase().trim();
    final String statusLabel = payment['status_label']?.toString() ?? '';

    // Couleurs pour les opérateurs
    Color operatorColor = const Color(0xFF7CB342);
    if (operator.contains('voda')) operatorColor = const Color(0xFFFF4B4B); // Rouge
    else if (operator.contains('airtel')) operatorColor = const Color(0xFFFF1744); // Rouge clair
    else if (operator.contains('orange')) operatorColor = const Color(0xFFFF9800); // Orange
    else if (operator.contains('africell')) operatorColor = const Color(0xFF9C27B0); // Violet

    final isSuccess = ['completed', 'success', 'successful', 'paid', 'approved', 'done'].contains(status);
    final isPending = ['pending', 'processing', 'waiting', 'initiated'].contains(status);

    String displayStatus;
    Color statusColor;

    if (isSuccess) {
      displayStatus = statusLabel.isNotEmpty ? statusLabel : 'Réussi';
      statusColor = const Color(0xFF38A169);
    } else if (isPending) {
      displayStatus = statusLabel.isNotEmpty ? statusLabel : 'En attente';
      statusColor = const Color(0xFFED8936);
    } else {
      displayStatus = statusLabel.isNotEmpty ? statusLabel : 'Échoué';
      statusColor = const Color(0xFFE53E3E);
    }

    final formatCdf = NumberFormat.currency(locale: 'fr_FR', symbol: 'CDF', decimalDigits: 0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Ligne 1: Date + Statut
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: textHint,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(date),
                  style: TextStyle(
                    color: textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    displayStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Ligne 2: Montant + Opérateur
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currency == 'CDF') ...[
                        Text(
                          formatCdf.format(amountRaw),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          '~ \$${amountUsd.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: operatorColor.withOpacity(0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else ...[
                        Text(
                          '\$${amountRaw.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 👇 LE NOUVEAU BADGE OPÉRATEUR TEXTUEL
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: operatorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: operatorColor.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _getNetworkLabel(operator),
                    style: TextStyle(
                      color: operatorColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Ligne 3: Référence
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_outlined,
                    size: 12,
                    color: textHint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Réf: ${payment['reference']}',
                      style: TextStyle(
                        color: textHint,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 👇 FONCTION POUR FORMATER LE NOM DU RÉSEAU
  String _getNetworkLabel(String operator) {
    if (operator.isEmpty || operator == 'inconnu') return 'Inconnu';
    if (operator.contains('voda')) return 'Vodacom';
    if (operator.contains('airtel')) return 'Airtel';
    if (operator.contains('orange')) return 'Orange';
    if (operator.contains('africell')) return 'Africell';

    // Si c'est un autre réseau non géré manuellement, on met juste la première lettre en majuscule
    return operator[0].toUpperCase() + operator.substring(1);
  }
}
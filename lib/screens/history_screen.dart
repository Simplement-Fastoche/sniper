import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../services/logger_service.dart';
import '../widgets/ErrorPopupWidget.dart';

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

  final String _apiUrl = 'https://admin.sniper-sarl.cloud/api/v1/payments';
  late final LoggerService _logger;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
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
      if (mounted) setState(() { _isLoading = true; _errorMessage = null; });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      if (token == null) {
        if (mounted) setState(() { _errorMessage = "Session expirée."; _isLoading = false; });
        return;
      }

      final url = Uri.parse('$_apiUrl?page=$_currentPage');
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
            "amount_cdf": attrs['amount']?.toString() ?? '0',
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
            if (refresh) _errorMessage = "Trop de requêtes. Veuillez patienter.";
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
            if (refresh) _errorMessage = "Impossible de charger l'historique.";
            _isLoading = false;
            _isFetchingMore = false;
          });
        }
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Payments', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          if (refresh) _errorMessage = "Erreur de réseau.";
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF6C63FF),
          strokeWidth: 3,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFFF6B6B)),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _fetchHistory(refresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
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
            Icon(Icons.receipt_long, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              "Aucun paiement récent.",
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchHistory(refresh: true),
      color: const Color(0xFF6C63FF),
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _payments.length + (_isFetchingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _payments.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCompactNeonPaymentCard(_payments[index]),
          );
        },
      ),
    );
  }

  // ==================== CARTE COMPACTE STYLE NEON ====================

  Widget _buildCompactNeonPaymentCard(Map<String, dynamic> payment) {
    final DateTime date = DateTime.tryParse(payment['date']) ?? DateTime.now();
    final double amountCdf = double.tryParse(payment['amount_cdf']) ?? 0.0;
    final double amountUsd = double.tryParse(payment['amount_usd']) ?? 0.0;
    final String operator = payment['network'].toString().toLowerCase();

    final String status = payment['status'].toString().toLowerCase().trim();
    final String statusLabel = payment['status_label']?.toString() ?? '';

    // Couleurs Néon pour les opérateurs
    Color operatorColor = const Color(0xFF6C63FF);
    if (operator.contains('voda')) operatorColor = const Color(0xFFFF4B4B);
    else if (operator.contains('airtel')) operatorColor = const Color(0xFFFF1744);
    else if (operator.contains('orange')) operatorColor = const Color(0xFFFF9800);
    else if (operator.contains('africell')) operatorColor = const Color(0xFF9C27B0);

    final isSuccess = ['completed', 'success', 'successful', 'paid', 'approved', 'done'].contains(status);
    final isPending = ['pending', 'processing', 'waiting', 'initiated'].contains(status);

    String displayStatus;
    Color statusColor;

    if (isSuccess) {
      displayStatus = statusLabel.isNotEmpty ? statusLabel : 'Réussi';
      statusColor = const Color(0xFF4CAF50);
    } else if (isPending) {
      displayStatus = statusLabel.isNotEmpty ? statusLabel : 'En attente';
      statusColor = const Color(0xFFFF9800);
    } else {
      displayStatus = statusLabel.isNotEmpty ? statusLabel : 'Échoué';
      statusColor = const Color(0xFFFF6B6B);
    }

    final formatCdf = NumberFormat.currency(locale: 'fr_FR', symbol: 'CDF', decimalDigits: 0);

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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: operatorColor.withOpacity(0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: operatorColor.withOpacity(0.12),
            blurRadius: 15,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            // Ligne 1: Date + Statut
            Row(
              children: [
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(date),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    displayStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Ligne 2: Montant + Opérateur
            Row(
              children: [
                // Montant
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatCdf.format(amountCdf),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '~ \$${amountUsd.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: operatorColor.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Icône opérateur
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [operatorColor.withOpacity(0.6), operatorColor.withOpacity(0.2)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getOperatorIcon(operator),
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Ligne 3: Référence
            Row(
              children: [
                Text(
                  'Réf: ${payment['reference']}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getOperatorIcon(String operator) {
    if (operator.contains('voda')) return Icons.signal_cellular_4_bar;
    if (operator.contains('airtel')) return Icons.wifi;
    if (operator.contains('orange')) return Icons.circle;
    if (operator.contains('africell')) return Icons.signal_wifi_4_bar;
    return Icons.cell_tower;
  }
}
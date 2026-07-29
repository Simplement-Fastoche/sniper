import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../services/logger_service.dart';
import '../widgets/ErrorPopupWidget.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _schedule = [];

  final bool _useMockApi = false;
  final String _apiUrl = 'https://admin.sniper-sarl.cloud/api/v1/schedule';

  late final LoggerService _logger;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _logger.init().then((_) {
      _logger.info('ScheduleScreen initialisé');
    });
    _fetchSchedule();
  }

  Future<void> _fetchSchedule() async {
    _logger.info('Tentative de chargement de l\'échéancier');

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      if (token == null) {
        _logger.warning('Token manquant, session expirée');
        setState(() {
          _errorMessage = "Session expirée. Veuillez vous reconnecter.";
          _isLoading = false;
        });
        _showError('Session expirée', 'Votre session a expiré. Veuillez vous reconnecter.');
        return;
      }

      int statusCode;
      String responseBody;

      if (_useMockApi) {
        await Future.delayed(const Duration(milliseconds: 1000));
        statusCode = 200;
        responseBody = jsonEncode({
          "data": [
            {
              "id": "1",
              "type": "contract-installments",
              "attributes": {
                "sequence": 1,
                "due_at": "2026-01-15T00:00:00.000Z",
                "amount_usd": "16.44",
                "paid_usd": "16.44",
                "remaining_usd": "0.00",
                "status": "paid",
                "status_label": "Payé"
              }
            },
            {
              "id": "2",
              "type": "contract-installments",
              "attributes": {
                "sequence": 2,
                "due_at": "2026-02-15T00:00:00.000Z",
                "amount_usd": "16.44",
                "paid_usd": "10.00",
                "remaining_usd": "6.44",
                "status": "partial",
                "status_label": "Partiel"
              }
            },
            {
              "id": "3",
              "type": "contract-installments",
              "attributes": {
                "sequence": 3,
                "due_at": "2026-03-15T00:00:00.000Z",
                "amount_usd": "16.44",
                "paid_usd": "0.00",
                "remaining_usd": "16.44",
                "status": "pending",
                "status_label": "En attente"
              }
            }
          ]
        });
      } else {
        final response = await http.get(
          Uri.parse(_apiUrl),
          headers: {
            'Accept': 'application/vnd.api+json',
            'Authorization': 'Bearer $token',
          },
        );
        statusCode = response.statusCode;
        responseBody = response.body;
      }

      _logger.info('=== API SCHEDULE ===', data: {
        'status_code': statusCode,
        'body': responseBody,
      });

      if (statusCode == 200) {
        try {
          final decodedData = jsonDecode(responseBody);
          final List<dynamic> rawData = decodedData['data'] ?? [];

          final List<Map<String, dynamic>> mappedSchedule = rawData.map((item) {
            final attrs = item['attributes'] ?? {};
            return {
              'id': item['id'],
              'sequence': attrs['sequence'],
              'due_at': attrs['due_at'],
              'amount_usd': attrs['amount_usd'],
              'paid_usd': attrs['paid_usd'],
              'remaining_usd': attrs['remaining_usd'],
              'status': attrs['status'],
              'status_label': attrs['status_label'],
            };
          }).toList();

          setState(() {
            _schedule = mappedSchedule;
            _isLoading = false;
          });

        } catch (e, stackTrace) {
          _logger.error('Erreur lors du décodage de l\'échéancier', data: {'body': responseBody}, error: e, stackTrace: stackTrace);
          setState(() {
            _errorMessage = "Erreur de traitement des données.";
            _isLoading = false;
          });
          _showError('Erreur de données', 'Impossible de lire les échéances.', onRetry: _fetchSchedule);
        }
      } else if (statusCode == 429) {
        _logger.warning('Rate limit atteint sur Schedule (429)');
        setState(() {
          _errorMessage = "Trop de requêtes. Veuillez patienter.";
          _isLoading = false;
        });
        _showError('Trop de tentatives', 'Veuillez patienter quelques instants avant de rafraîchir l\'échéancier.', onRetry: _fetchSchedule);
      } else if (statusCode == 401 || statusCode == 403) {
        _logger.warning('Accès refusé ($statusCode)');
        setState(() {
          _errorMessage = "Session expirée ou accès refusé.";
          _isLoading = false;
        });
        _showError('Accès refusé', 'Votre session a expiré. Veuillez vous reconnecter.');
      } else {
        _logger.warning('Erreur API Schedule', data: {'status': statusCode});
        setState(() {
          _errorMessage = "Impossible de charger l'échéancier.";
          _isLoading = false;
        });
        _showError('Erreur serveur', 'Le serveur a renvoyé une erreur (Code: $statusCode).', onRetry: _fetchSchedule);
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Schedule', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = "Erreur de connexion au serveur.";
        _isLoading = false;
      });
      _showError('Erreur de connexion', 'Impossible de joindre le serveur. Vérifiez votre connexion internet.', onRetry: _fetchSchedule);
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
    return Container(
      color: const Color(0xFF0A0A1A),
      child: _buildBody(),
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
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _fetchSchedule();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_schedule.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              "Aucune échéance trouvée.",
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSchedule,
      color: const Color(0xFF6C63FF),
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _schedule.length,
        itemBuilder: (context, index) {
          final item = _schedule[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCompactNeonScheduleCard(item),
          );
        },
      ),
    );
  }

  // ==================== CARTE COMPACTE STYLE NEON ====================

  Widget _buildCompactNeonScheduleCard(Map<String, dynamic> item) {
    final DateTime date = item['due_at'] != null ? DateTime.parse(item['due_at']) : DateTime.now();
    final double montant = double.tryParse(item['amount_usd']?.toString() ?? '0') ?? 0.0;
    final double paye = double.tryParse(item['paid_usd']?.toString() ?? '0') ?? 0.0;
    final double reste = double.tryParse(item['remaining_usd']?.toString() ?? '0') ?? 0.0;

    final String statut = item['status']?.toString() ?? 'pending';
    final String statusLabel = item['status_label']?.toString() ?? '';
    final int sequence = int.tryParse(item['sequence']?.toString() ?? '0') ?? 0;

    Color statusColor;
    String text;
    IconData icon;

    switch (statut.toLowerCase()) {
      case 'paid':
        statusColor = const Color(0xFF4CAF50);
        text = 'Payé';
        icon = Icons.check_circle;
        break;
      case 'partial':
        statusColor = const Color(0xFFFF9800);
        text = 'Partiel';
        icon = Icons.timelapse;
        break;
      case 'overdue':
        statusColor = const Color(0xFFFF6B6B);
        text = 'En retard';
        icon = Icons.warning;
        break;
      case 'pending':
      default:
        statusColor = const Color(0xFF6C63FF);
        text = 'En attente';
        icon = Icons.schedule;
        break;
    }

    final finalText = statusLabel.isNotEmpty ? statusLabel : text;

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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withOpacity(0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            // Ligne 1: Séquence + Date + Statut
            Row(
              children: [
                // Numéro de séquence
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [statusColor, statusColor.withOpacity(0.5)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      sequence.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('dd/MM/yyyy').format(date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE').format(date),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                // Statut
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        statusColor.withOpacity(0.15),
                        statusColor.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        finalText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Ligne 2: Montants
            Row(
              children: [
                _buildCompactAmount('Total', montant, Colors.white),
                const SizedBox(width: 16),
                _buildCompactAmount('Payé', paye, const Color(0xFF4CAF50)),
                const SizedBox(width: 16),
                _buildCompactAmount('Reste', reste, reste > 0 ? statusColor : Colors.white.withOpacity(0.3)),
              ],
            ),
            // Barre de progression
            if (montant > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (paye / montant).clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    paye >= montant ? const Color(0xFF4CAF50) : statusColor,
                  ),
                  minHeight: 4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAmount(String label, double amount, Color color) {
    final bool hasGlow = color != Colors.white && color != Colors.white.withOpacity(0.3);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Colors.white.withOpacity(0.4),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${amount.toStringAsFixed(2)} \$',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              shadows: hasGlow ? [
                Shadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 6,
                ),
              ] : null,
            ),
          ),
        ],
      ),
    );
  }
}
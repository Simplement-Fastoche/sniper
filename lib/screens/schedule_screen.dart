import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sniper/screens/payment_screen.dart';

import '../config/app_colors.dart';
import '../services/logger_service.dart';
import '../services/theme_service.dart';
import '../config/api_config.dart';

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

  late final LoggerService _logger;
  late final ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _themeService = ThemeService();
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
          Uri.parse(ApiConfig.scheduleEndpoint),
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
        }
      } else if (statusCode == 429) {
        _logger.warning('Rate limit atteint sur Schedule (429)');
        setState(() {
          _errorMessage = "Trop de requêtes. Veuillez patienter.";
          _isLoading = false;
        });
      } else if (statusCode == 401 || statusCode == 403) {
        _logger.warning('Accès refusé ($statusCode)');
        setState(() {
          _errorMessage = "Session expirée ou accès refusé.";
          _isLoading = false;
        });
      } else {
        _logger.warning('Erreur API Schedule', data: {'status': statusCode});
        setState(() {
          _errorMessage = "Impossible de charger l'échéancier.";
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Schedule', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = "Erreur de connexion au serveur.";
        _isLoading = false;
      });
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
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _fetchSchedule();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7CB342),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text('Réessayer'),
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
            Icon(
              Icons.calendar_today,
              size: 64,
              color: textHint,
            ),
            const SizedBox(height: 16),
            Text(
              "Aucune échéance trouvée.",
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
      onRefresh: _fetchSchedule,
      color: const Color(0xFF7CB342),
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _schedule.length,
        itemBuilder: (context, index) {
          final item = _schedule[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildScheduleCard(
              item: item,
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

  // ==================== CARTE SCHEDULE STYLE ÉLÉGANT ====================
  Widget _buildScheduleCard({
    required Map<String, dynamic> item,
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
  }) {
    // 👇 CONVERSION ICI AVEC .toLocal()
    final DateTime date = item['due_at'] != null ? DateTime.parse(item['due_at']).toLocal() : DateTime.now();
    final double montant = double.tryParse(item['amount_usd']?.toString() ?? '0') ?? 0.0;
    final double paye = double.tryParse(item['paid_usd']?.toString() ?? '0') ?? 0.0;
    final double reste = double.tryParse(item['remaining_usd']?.toString() ?? '0') ?? 0.0;
    final int sequence = int.tryParse(item['sequence']?.toString() ?? '0') ?? 0;

    Color statusColor;
    String text;
    IconData icon;

    final now = DateTime.now();
    final isOverdue = DateTime(now.year, now.month, now.day).isAfter(DateTime(date.year, date.month, date.day));

    if (paye >= montant && montant > 0) {
      statusColor = const Color(0xFF38A169); // Vert
      text = 'Payé';
      icon = Icons.check_circle;
    } else if (isOverdue) {
      statusColor = const Color(0xFFE53E3E); // Rouge
      text = 'En retard';
      icon = Icons.warning;
    } else if (paye > 0) {
      statusColor = const Color(0xFFF59E0B); // Jaune/Ambré
      text = 'Partiellement payé';
      icon = Icons.timelapse;
    } else {
      statusColor = const Color(0xFF3182CE); // Bleu
      text = 'À payer';
      icon = Icons.schedule;
    }

    String dayName = DateFormat('EEEE', 'fr_FR').format(date);
    if (dayName.isNotEmpty) {
      dayName = '${dayName[0].toUpperCase()}${dayName.substring(1)}';
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            // Ligne 1: Séquence + Date + Statut
            Row(
              children: [
                // Numéro de séquence
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7CB342), Color(0xFF558B2F)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7CB342).withOpacity(0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      sequence.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
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
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 11,
                          color: textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                // Statut (BADGE)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        text,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Ligne 2: Montants
            Row(
              children: [
                _buildAmountItem(
                  label: 'Total',
                  amount: montant,
                  color: textPrimary,
                  textHint: textHint,
                ),
                const SizedBox(width: 16),
                _buildAmountItem(
                  label: 'Payé',
                  amount: paye,
                  color: const Color(0xFF38A169),
                  textHint: textHint,
                ),
                const SizedBox(width: 16),
                _buildAmountItem(
                  label: 'Reste',
                  amount: reste,
                  color: reste > 0 ? statusColor : textHint.withOpacity(0.5),
                  textHint: textHint,
                ),
              ],
            ),
            // Barre de progression
            if (montant > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (paye / montant).clamp(0.0, 1.0),
                  backgroundColor: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFCBD5E1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    paye >= montant ? const Color(0xFF38A169) : statusColor,
                  ),
                  minHeight: 4,
                ),
              ),
              // Pourcentage
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${((paye / montant) * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: textHint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAmountItem({
    required String label,
    required double amount,
    required Color color,
    required Color textHint,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${amount.toStringAsFixed(2)} \$',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
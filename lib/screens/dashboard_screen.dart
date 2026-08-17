import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sniper/screens/activation_screen.dart';
import 'package:sniper/screens/payment_screen.dart';
import 'package:sniper/screens/schedule_screen.dart';
import '../config/api_config.dart';
import '../config/app_colors.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';
import '../services/theme_service.dart';

import '../widgets/ErrorPopupWidget.dart';
import '../widgets/drawer_widget.dart';
import '../widgets/bottom_nav_widget.dart';
import 'history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  User _user = User.currentUser();
  late final LoggerService _logger;
  bool _isLoading = true;
  String? _errorMessage;

  bool _isSessionRevoked = false;

  Map<String, dynamic>? _dashboardData;
  late ThemeService _themeService;

  Key _refreshKey = UniqueKey();

  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _themeService = ThemeService();
    _logger.init().then((_) {
      _logger.info('DashboardScreen initialisé');
    });
    _user = User(name: "Chargement...", email: "", avatarUrl: "", phoneNumber: "", branch: "");
    _fetchDashboardData();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _dashboardData != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleGlobalRefresh() async {
    setState(() {
      _refreshKey = UniqueKey();
    });
    await _fetchDashboardData();
  }

  Future<void> _logoutAndReactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const ActivationScreen()),
            (route) => false,
      );
    }
  }

  Future<void> _fetchDashboardData() async {
    _logger.info('Tentative de chargement du dashboard');

    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isSessionRevoked = false;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      if (token == null) {
        _logger.warning('Token manquant, session expirée');
        setState(() {
          _isSessionRevoked = true;
          _errorMessage = "Session expirée. L'appareil nécessite une réactivation.";
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse(ApiConfig.meEndpoint),
        headers: {
          'Accept': 'application/vnd.api+json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        try {
          final decodedResponse = jsonDecode(response.body);
          final attributes = decodedResponse['data']['attributes'];

          final profile = attributes['profile'] ?? {};
          final phones = profile['phones'] as List<dynamic>? ?? [];

          String mainPhone = 'Non renseigné';
          for (var phone in phones) {
            if (phone['primary'] == true || phone['primary'] == 1) {
              mainPhone = phone['number'] ?? 'Non renseigné';
              break;
            }
          }
          if (mainPhone == 'Non renseigné' && phones.isNotEmpty) {
            mainPhone = phones[0]['number'] ?? 'Non renseigné';
          }

          String avatarUrl = '${ApiConfig.fallbackAvatarUrl}?name=${attributes['display_name'] ?? 'Client'}&background=7CB342&color=fff';

          if (profile['photo'] != null) {
            if (profile['photo'] is Map) {
              if (profile['photo']['url'] != null && profile['photo']['url'].toString().isNotEmpty) {
                avatarUrl = profile['photo']['url'].toString();
              }
            } else if (profile['photo'] is String) {
              if (profile['photo'].toString().isNotEmpty) {
                avatarUrl = profile['photo'].toString();
              }
            }
          }

          setState(() {
            _dashboardData = _mapApiDataToDashboard(attributes);
            _user = User(
              name: attributes['display_name'] ?? 'Client Inconnu',
              email: 'Client WonyaPay',
              avatarUrl: avatarUrl,
              phoneNumber: mainPhone,
              branch: attributes['contract_number'] ?? 'Standard',
            );
            _isLoading = false;
          });
        } catch (e, stackTrace) {
          _logger.error('Erreur lors du décodage', data: {'body': response.body}, error: e, stackTrace: stackTrace);
          setState(() {
            _errorMessage = "Erreur de traitement des données.";
            _isLoading = false;
          });
        }
      } else if (response.statusCode == 429) {
        setState(() {
          _errorMessage = "Trop de requêtes. Veuillez patienter un instant.";
          _isLoading = false;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() {
          _isSessionRevoked = true;
          _errorMessage = "La session a été révoquée par l'administrateur. Veuillez réactiver l'appareil.";
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Erreur serveur (Code: ${response.statusCode}).";
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Dashboard', error: e, stackTrace: stackTrace);
      setState(() {
        _errorMessage = "Erreur de connexion au serveur.";
        _isLoading = false;
      });
    }
  }

  void _showError(String title, String message, {Map<String, dynamic>? details, VoidCallback? onRetry}) {
    if (mounted) {
      ErrorPopupWidget.showErrorDialog(
        context,
        title: title,
        message: message,
        details: details,
        showAllLogs: false,
        onRetry: onRetry,
      );
    }
  }

  Map<String, dynamic> _mapApiDataToDashboard(Map<String, dynamic> apiData) {
    final contract = apiData['contract'] ?? {};
    final paymentEquivalents = contract['payment_equivalents'] ?? {};
    final pointOfSale = contract['point_of_sale'] ?? {};
    final device = contract['device'] ?? {};
    final specifications = device['specifications'] ?? {};
    final profile = apiData['profile'] ?? {};

    final paymentSummary = contract['payment_summary'] ?? {};
    final nextInstallment = paymentSummary['next_installment'] ?? {};
    final lastPayment = paymentSummary['last_successful_payment'];

    String brand = device['brand']?.toString().trim() ?? '';
    String rawModel = device['model']?.toString().trim() ?? apiData['device_model']?.toString().trim() ?? 'Appareil';

    String fullDeviceName = rawModel;
    if (brand.isNotEmpty && !rawModel.toLowerCase().contains(brand.toLowerCase())) {
      fullDeviceName = '$brand $rawModel';
    }

    String shortModel = rawModel;
    if (brand.isNotEmpty && rawModel.toLowerCase().startsWith(brand.toLowerCase())) {
      shortModel = rawModel.substring(brand.length).trim();
    }
    if (shortModel.isEmpty) shortModel = rawModel;

    String firstName = profile['first_name']?.toString() ?? '';
    String lastName = profile['last_name']?.toString() ?? '';
    String clientName = apiData['display_name'] ?? '$firstName $lastName'.trim();
    if (clientName.isEmpty) clientName = 'Client Inconnu';

    final witnessesList = contract['witnesses'] as List<dynamic>? ?? [];
    final witnesses = witnessesList.map((w) {
      return {
        'name': w['name']?.toString() ?? 'Témoin',
        'phone': w['phone']?.toString() ?? 'Non renseigné',
        'relationship': w['relationship_label']?.toString() ?? 'Relation non précisée',
      };
    }).toList();

    String storageDisplay = '-';
    final storageVal = specifications['storage_gb']?.toString();
    if (storageVal != null && storageVal.isNotEmpty && storageVal != '0' && storageVal != '0.0') {
      storageDisplay = '$storageVal Go';
    }

    String ramDisplay = '-';
    final ramVal = specifications['ram_gb']?.toString();
    if (ramVal != null && ramVal.isNotEmpty && ramVal != '0' && ramVal != '0.0') {
      ramDisplay = '$ramVal Go';
    }

    return {
      'client': {
        'nom': clientName,
        'telephone': 'Non renseigné',
      },
      'contrat': {
        'reference': apiData['contract_number'] ?? 'N/A',
        'statut': apiData['status_label'] ?? 'Actif',
      },
      'telephone': {
        'nomComplet': fullDeviceName,
        'modeleCourt': shortModel,
        'imei1': apiData['device_imei_suffix'] != null ? '***${apiData['device_imei_suffix']}' : 'N/A',
        'imei2': 'N/A',
        'couleur': '-',
        'stockage': storageDisplay,
        'ram': ramDisplay,
        'statut': apiData['status_label'] ?? 'Actif',
        'reference_contrat': apiData['contract_number'] ?? 'N/A',
      },
      'financier': {
        'prixTotal': double.tryParse(paymentSummary['total_price_usd']?.toString() ?? '0') ?? 0.0,
        'montantPaye': double.tryParse(paymentSummary['total_paid_usd']?.toString() ?? '0') ?? 0.0,
        'soldeRestant': double.tryParse(paymentSummary['outstanding_usd']?.toString() ?? '0') ?? 0.0,

        'montantHoraire': double.tryParse(paymentEquivalents['hourly_usd']?.toString() ?? '0') ?? 0.0,
        'montantMensuel': double.tryParse(paymentEquivalents['monthly_usd']?.toString() ?? '0') ?? 0.0,
        'montantHebdomadaire': double.tryParse(paymentEquivalents['weekly_usd']?.toString() ?? '0') ?? 0.0,
        'montantJournalier': double.tryParse(paymentEquivalents['daily_usd']?.toString() ?? '0') ?? 0.0,
      },
      'paiements': {
        'prochaineEcheance': nextInstallment['due_at'] != null
            ? DateTime.parse(nextInstallment['due_at']).toLocal()
            : DateTime.now().add(const Duration(days: 30)).toLocal(),

        'nextLockAt': paymentSummary['next_lock_at'] != null
            ? DateTime.parse(paymentSummary['next_lock_at']).toLocal()
            : null,
        'lockOverdue': paymentSummary['lock_overdue'] == true,

        'montantEcheance': double.tryParse(nextInstallment['amount_usd']?.toString() ?? '0') ?? 0.0,
        'payeEcheance': double.tryParse(nextInstallment['paid_usd']?.toString() ?? '0') ?? 0.0,
        'isOverdue': nextInstallment['overdue'] == true,

        'dernierPaiement': lastPayment != null ? {
          'date': DateTime.parse(lastPayment['completed_at'] ?? DateTime.now().toIso8601String()).toLocal(),
          'montant': double.tryParse(lastPayment['credited_usd']?.toString() ?? '0') ?? 0.0,
        } : null,
      },
      'detailsContrat': {
        'numeroContrat': apiData['contract_number'] ?? 'N/A',
        'nomClient': clientName,
        'duree': contract['duration_months']?.toString() ?? '-',
        'pointDeVente': pointOfSale['name']?.toString() ?? 'Non renseigné',
        'dateLivraison': contract['delivered_at'] != null
            ? DateTime.parse(contract['delivered_at']).toLocal()
            : null,
        'temoins': witnesses,
      },
    };
  }

  String _formatDuration(Duration duration) {
    int days = duration.inDays;
    int hours = duration.inHours.remainder(24);
    int minutes = duration.inMinutes.remainder(60);
    int seconds = duration.inSeconds.remainder(60);

    String result = "";
    if (days > 0) result += "${days.toString().padLeft(2, '0')}Jours, ";
    result += "${hours.toString().padLeft(2, '0')}Heures, ";
    result += "${minutes.toString().padLeft(2, '0')} minutes; ";
    result += "${seconds.toString().padLeft(2, '0')}Seconde${seconds > 1 ? 's' : ''}";

    return result;
  }

  bool _hasUrgentNotification() {
    if (_dashboardData == null) return false;

    final solde = _dashboardData!['financier']['soldeRestant'] as double;
    if (solde <= 0) return false;

    final lockOverdue = _dashboardData!['paiements']['lockOverdue'] as bool;
    if (lockOverdue) return true;

    final isOverdue = _dashboardData!['paiements']['isOverdue'] as bool;
    if (isOverdue) return true;

    final prochaineEcheance = _dashboardData!['paiements']['prochaineEcheance'] as DateTime;
    final now = DateTime.now();
    final difference = prochaineEcheance.difference(now).inDays;

    return difference <= 3;
  }

  void _refreshTheme() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeService.isDarkMode;
    final bgColor = isDark ? const Color(0xFF0F0F1A) : AppColors.background;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : AppColors.cardBackground;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadow;
    final textPrimary = isDark ? Colors.white : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFFB0B0C0) : AppColors.textSecondary;
    final textHint = isDark ? const Color(0xFF6B7280) : AppColors.textHint;
    final inputBorder = isDark ? const Color(0xFF3D3D5C) : AppColors.inputBorder;
    final backgroundAlt = isDark ? const Color(0xFF2D2D44) : AppColors.backgroundAlt;

    final bool isAppBlocked = _errorMessage != null || _isSessionRevoked;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: isAppBlocked ? null : PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: shadow,
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: Icon(
                    Icons.menu,
                    color: textPrimary,
                    size: 26,
                  ),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: Text(
                _getAppBarTitle(),
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: textPrimary,
                    size: 26,
                  ),
                  onPressed: _handleGlobalRefresh,
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_outlined,
                        color: textPrimary,
                        size: 26,
                      ),
                      onPressed: () => _showNotifications(context),
                    ),
                    if (_hasUrgentNotification())
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              iconTheme: IconThemeData(
                color: textPrimary,
              ),
            ),
          ),
        ),
      ),
      drawer: isAppBlocked ? null : CustomDrawer(
        user: _user,
        isDarkMode: isDark,
        onMenuItemSelected: (index) {
          Navigator.pop(context);
          if (index != -1) {
            setState(() {
              _currentIndex = index;
            });
          }
        },
        onThemeToggle: () async {
          await _themeService.setThemeMode(!isDark);
          _refreshTheme();
        },
      ),
      body: isAppBlocked
          ? _buildErrorScreen(textPrimary)
          : RefreshIndicator(
        onRefresh: _handleGlobalRefresh,
        color: AppColors.primary,
        backgroundColor: cardBg,
        child: _buildSelectedTab(
          isDark: isDark,
          cardBg: cardBg,
          shadow: shadow,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textHint: textHint,
          inputBorder: inputBorder,
          backgroundAlt: backgroundAlt,
        ),
      ),
      bottomNavigationBar: isAppBlocked
          ? null
          : SafeArea(
        child: CustomBottomNav(
          currentIndex: _currentIndex,
          isDarkMode: isDark,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildErrorScreen(Color textPrimary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isSessionRevoked ? AppColors.error.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  _isSessionRevoked ? Icons.gpp_bad_rounded : Icons.error_outline,
                  color: _isSessionRevoked ? AppColors.error : AppColors.warning,
                  size: 72
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _isSessionRevoked ? "Accès Révoqué" : "Erreur de chargement",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textPrimary
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? "Une erreur inconnue est survenue.",
              style: TextStyle(
                  fontSize: 16,
                  color: textPrimary.withOpacity(0.8),
                  height: 1.5
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            if (_isSessionRevoked)
              ElevatedButton.icon(
                onPressed: _logoutAndReactivate,
                icon: const Icon(Icons.lock_reset, color: Colors.white),
                label: const Text(
                  'Réactiver l\'appareil',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _handleGlobalRefresh,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                    'Réessayer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTab({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color backgroundAlt,
  }) {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardContent(
          isDark: isDark,
          cardBg: cardBg,
          shadow: shadow,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textHint: textHint,
          inputBorder: inputBorder,
          backgroundAlt: backgroundAlt,
        );
      case 1:
        return PaymentScreen(key: _refreshKey);
      case 2:
        return ScheduleScreen(key: _refreshKey);
      case 3:
        return HistoryScreen(key: _refreshKey);
      default:
        return _buildDashboardContent(
          isDark: isDark,
          cardBg: cardBg,
          shadow: shadow,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textHint: textHint,
          inputBorder: inputBorder,
          backgroundAlt: backgroundAlt,
        );
    }
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0: return 'Dashboard';
      case 1: return 'Payer';
      case 2: return 'Mon Échéancier';
      case 3: return 'Historique des paiements';
      default: return 'Dashboard';
    }
  }

  Widget _buildDashboardContent({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color backgroundAlt,
  }) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 100),
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _buildPhoneContractCard(
                  isDark: isDark,
                  cardBg: cardBg,
                  shadow: shadow,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textHint: textHint,
                  inputBorder: inputBorder,
                  backgroundAlt: backgroundAlt,
                ),
                const SizedBox(height: 14),

                if (_dashboardData!['paiements']['nextLockAt'] != null && _dashboardData!['financier']['soldeRestant'] > 0) ...[
                  _buildCountdownCard(
                    cardBg: cardBg,
                    shadow: shadow,
                  ),
                  const SizedBox(height: 14),
                ],

                _buildFinancialCard(
                  isDark: isDark,
                  cardBg: cardBg,
                  shadow: shadow,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textHint: textHint,
                  inputBorder: inputBorder,
                  backgroundAlt: backgroundAlt,
                ),
                const SizedBox(height: 14),

                _buildContractDetailsCard(
                  isDark: isDark,
                  cardBg: cardBg,
                  shadow: shadow,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textHint: textHint,
                  inputBorder: inputBorder,
                  backgroundAlt: backgroundAlt,
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

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
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
    required Color textPrimary,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // 👇 Rendu plus compact pour s'adapter à la ligne
  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {required Color textHint, required Color textPrimary}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: textHint, fontSize: 9)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider({required Color inputBorder}) {
    return Container(
      width: 1,
      height: 28,
      color: inputBorder,
    );
  }

  Widget _buildCountdownCard({
    required Color cardBg,
    required List<BoxShadow> shadow,
  }) {
    final paiements = _dashboardData!['paiements'];
    final DateTime nextLockAt = paiements['nextLockAt'];
    final bool lockOverdue = paiements['lockOverdue'];

    final now = DateTime.now();
    Duration diff;

    final bool isOverdue = lockOverdue || now.isAfter(nextLockAt);

    if (isOverdue) {
      diff = now.difference(nextLockAt);
    } else {
      diff = nextLockAt.difference(now);
    }

    final String days = diff.inDays.toString().padLeft(2, '0');
    final String hours = diff.inHours.remainder(24).toString().padLeft(2, '0');
    final String minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');

    final isDark = _themeService.isDarkMode;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A202C);
    final textHint = isDark ? const Color(0xFF6B7280) : const Color(0xFFA0AEC0);
    final boxBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(
                isOverdue ? Icons.lock : Icons.lock_open,
                color: isOverdue ? AppColors.error : const Color(0xFF3182CE),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isOverdue ? "APPAREIL BLOQUÉ DEPUIS :" : "PROCHAIN BLOCAGE DANS :",
                style: TextStyle(
                  color: isOverdue ? AppColors.error : textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),

        // Grille du compte à rebours uniquement
        Row(
          children: [
            Expanded(child: _buildTimeBox('JOURS', days, isOverdue, boxBg, textPrimary, textHint, shadow)),
            const SizedBox(width: 10),
            Expanded(child: _buildTimeBox('HEURES', hours, isOverdue, boxBg, textPrimary, textHint, shadow)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildTimeBox('MINUTES', minutes, isOverdue, boxBg, textPrimary, textHint, shadow)),
            const SizedBox(width: 10),
            Expanded(child: _buildTimeBox('SECONDES', seconds, isOverdue, boxBg, textPrimary, textHint, shadow)),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeBox(
      String label,
      String value,
      bool isOverdue,
      Color bg,
      Color textPrimary,
      Color textHint,
      List<BoxShadow> shadow
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOverdue ? AppColors.error : AppColors.warning,
                    boxShadow: [
                      BoxShadow(
                        color: (isOverdue ? AppColors.error : AppColors.warning).withOpacity(0.4),
                        blurRadius: 4,
                      )
                    ]
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textHint,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: isOverdue ? AppColors.error : textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneContractCard({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color backgroundAlt,
  }) {
    final telephone = _dashboardData!['telephone'];

    String maskImei(String imei) {
      if (imei.length <= 8) return imei;
      return '${imei.substring(0, 4)}****${imei.substring(imei.length - 4)}';
    }

    return _buildCard(
      cardBg: cardBg,
      shadow: shadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: const Icon(Icons.phone_android, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      telephone['nomComplet'] ?? 'Appareil',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withOpacity(0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          telephone['statut'],
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: backgroundAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: Center(
                    child: _buildDetailItem('Modèle', telephone['modeleCourt'] ?? '-', textHint: textHint, textPrimary: textPrimary),
                  ),
                ),
                _buildDivider(inputBorder: inputBorder),
                Expanded(
                  child: Center(
                    child: _buildDetailItem('Stockage', telephone['stockage'] ?? '-', textHint: textHint, textPrimary: textPrimary),
                  ),
                ),
                _buildDivider(inputBorder: inputBorder),
                Expanded(
                  child: Center(
                    child: _buildDetailItem('RAM', telephone['ram'] ?? '-', textHint: textHint, textPrimary: textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: backgroundAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('IMEI 1', style: TextStyle(color: textHint, fontSize: 9)),
                            Text(
                              maskImei(telephone['imei1']),
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDivider(inputBorder: inputBorder),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('IMEI 2', style: TextStyle(color: textHint, fontSize: 9)),
                            Text(
                              maskImei(telephone['imei2']),
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 👇 LIGNE DE DATE ULTRA-COMPACTE (Ajustée pour gagner de la place)
  Widget _buildCompactDateRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String badgeLabel,
    required Color badgeColor,
    required Color textPrimary,
    required Color textHint,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(6), // Réduit pour être plus compact
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16), // Icone légèrement plus petite
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: textHint, fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12, // Parfait pour inclure l'heure sans déborder
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        _buildInfoChip(badgeLabel, badgeColor),
      ],
    );
  }

  Widget _buildFinancialCard({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color backgroundAlt,
  }) {
    final financier = _dashboardData!['financier'];
    final paiements = _dashboardData!['paiements'];

    // Variables pour l'échéance
    final prochaineEcheance = paiements['prochaineEcheance'] as DateTime;
    final isOverdue = paiements['isOverdue'] as bool;
    final montantEcheance = paiements['montantEcheance'] as double;
    final payeEcheance = paiements['payeEcheance'] as double;

    // Variables pour le blocage
    final DateTime? nextLockAt = paiements['nextLockAt'];
    final bool lockOverdue = paiements['lockOverdue'] == true;

    // Variables pour le dernier paiement
    final dernierPaiement = paiements['dernierPaiement'];

    String echeanceBadgeLabel = 'À venir';
    Color echeanceBadgeColor = const Color(0xFF3182CE);

    if (payeEcheance >= montantEcheance && montantEcheance > 0) {
      echeanceBadgeLabel = 'Payé';
      echeanceBadgeColor = AppColors.success;
    } else if (isOverdue) {
      echeanceBadgeLabel = 'En retard';
      echeanceBadgeColor = AppColors.error;
    } else if (payeEcheance > 0) {
      echeanceBadgeLabel = 'Partiel';
      echeanceBadgeColor = AppColors.warning;
    }

    return _buildCard(
      cardBg: cardBg,
      shadow: shadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Finances',
            icon: Icons.account_balance_wallet,
            color: AppColors.secondary,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildFinancialItem(
                  label: 'Total',
                  value: '${financier['prixTotal'].toStringAsFixed(2)} \$',
                  color: textPrimary,
                ),
              ),
              _buildDivider(inputBorder: inputBorder),
              Expanded(
                child: _buildFinancialItem(
                  label: 'Payé',
                  value: '${financier['montantPaye'].toStringAsFixed(2)} \$',
                  color: AppColors.success,
                ),
              ),
              _buildDivider(inputBorder: inputBorder),
              Expanded(
                child: _buildFinancialItem(
                  label: 'Solde',
                  value: '${financier['soldeRestant'].toStringAsFixed(2)} \$',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),

          // 👇 BLOC DES 3 DATES (Heure ajoutée, design affiné avec bordure)
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: inputBorder.withOpacity(0.3)), // Bordure élégante
            ),
            child: Column(
              children: [
                // 1. Prochaine Échéance
                _buildCompactDateRow(
                  icon: Icons.calendar_today,
                  iconColor: AppColors.secondary,
                  title: 'Prochaine échéance',
                  // Format Date + Heure
                  value: DateFormat("dd/MM/yyyy 'à' HH:mm", 'fr_FR').format(prochaineEcheance),
                  badgeLabel: echeanceBadgeLabel,
                  badgeColor: echeanceBadgeColor,
                  textPrimary: textPrimary,
                  textHint: textHint,
                ),

                // 2. Prochain Blocage
                if (nextLockAt != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: inputBorder.withOpacity(0.3), height: 1, thickness: 1),
                  ),
                  _buildCompactDateRow(
                    icon: lockOverdue ? Icons.lock : Icons.timer_outlined,
                    iconColor: lockOverdue ? AppColors.error : AppColors.warning,
                    title: lockOverdue ? 'Bloqué depuis le' : 'Prochain blocage',
                    // Format Date + Heure
                    value: DateFormat("dd/MM/yyyy 'à' HH:mm", 'fr_FR').format(nextLockAt),
                    badgeLabel: lockOverdue ? 'Bloqué' : 'En attente',
                    badgeColor: lockOverdue ? AppColors.error : AppColors.warning,
                    textPrimary: textPrimary,
                    textHint: textHint,
                  ),
                ],

                // 3. Dernier Paiement
                if (dernierPaiement != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: inputBorder.withOpacity(0.3), height: 1, thickness: 1),
                  ),
                  _buildCompactDateRow(
                    icon: Icons.payment,
                    iconColor: AppColors.success,
                    title: 'Dernier paiement',
                    // Format Date + Heure
                    value: DateFormat("dd/MM/yyyy 'à' HH:mm", 'fr_FR').format(dernierPaiement['date']),
                    badgeLabel: '+ ${dernierPaiement['montant']} \$',
                    badgeColor: AppColors.success,
                    textPrimary: textPrimary,
                    textHint: textHint,
                  ),
                ]
              ],
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSmallFinancialItem(
                  'Horaire',
                  '${financier['montantHoraire']} \$',
                  textHint: textHint,
                  textPrimary: textPrimary,
                  backgroundAlt: backgroundAlt,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSmallFinancialItem(
                  'Journalier',
                  '${financier['montantJournalier']} \$',
                  textHint: textHint,
                  textPrimary: textPrimary,
                  backgroundAlt: backgroundAlt,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSmallFinancialItem(
                  'Hebdo',
                  '${financier['montantHebdomadaire']} \$',
                  textHint: textHint,
                  textPrimary: textPrimary,
                  backgroundAlt: backgroundAlt,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSmallFinancialItem(
                  'Mensuel',
                  '${financier['montantMensuel']} \$',
                  textHint: textHint,
                  textPrimary: textPrimary,
                  backgroundAlt: backgroundAlt,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialItem({required String label, required String value, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallFinancialItem(
      String label,
      String value, {
        required Color textHint,
        required Color textPrimary,
        required Color backgroundAlt,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: textHint, fontSize: 9)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContractDetailsCard({
    required bool isDark,
    required Color cardBg,
    required List<BoxShadow> shadow,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color inputBorder,
    required Color backgroundAlt,
  }) {
    final details = _dashboardData!['detailsContrat'];
    final temoins = details['temoins'] as List<dynamic>;

    return _buildCard(
      cardBg: cardBg,
      shadow: shadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Détails du Contrat',
            icon: Icons.assignment_outlined,
            color: AppColors.primary,
            textPrimary: textPrimary,
          ),
          const SizedBox(height: 16),

          // Numéro de contrat et Nom du client
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: backgroundAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.tag, color: AppColors.primary, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Numéro de Contrat', style: TextStyle(color: textHint, fontSize: 10)),
                          Text(
                            details['numeroContrat'],
                            style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: inputBorder, height: 1),
                ),
                Row(
                  children: [
                    const Icon(Icons.person_outline, color: AppColors.primary, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Titulaire du Contrat', style: TextStyle(color: textHint, fontSize: 10)),
                          Text(
                            details['nomClient'],
                            style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Point de vente
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: backgroundAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront, color: AppColors.primary, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Point de vente', style: TextStyle(color: textHint, fontSize: 10)),
                      Text(
                        details['pointDeVente'],
                        style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Durée et Livraison
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timelapse, size: 16, color: textHint),
                          const SizedBox(width: 6),
                          Text('Durée', style: TextStyle(color: textHint, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${details['duree']} mois',
                        style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundAlt,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_month, size: 16, color: textHint),
                          const SizedBox(width: 6),
                          Text('Livraison', style: TextStyle(color: textHint, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        details['dateLivraison'] != null
                            ? DateFormat('dd/MM/yyyy').format(details['dateLivraison'])
                            : '-',
                        style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Témoins (si présents)
          if (temoins.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Témoins de garantie', style: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...temoins.map((t) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: backgroundAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: inputBorder.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.people_outline, size: 16, color: AppColors.secondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['name'], style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('${t['relationship']} • ${t['phone']}', style: TextStyle(color: textHint, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ]
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    final isDark = _themeService.isDarkMode;
    final bgColor = isDark ? const Color(0xFF1E1E2E) : AppColors.cardBackground;
    final textPrimary = isDark ? Colors.white : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFFB0B0C0) : AppColors.textSecondary;
    final inputBorder = isDark ? const Color(0xFF3D3D5C) : AppColors.inputBorder;

    List<Widget> notificationWidgets = [];

    if (_dashboardData != null) {
      final solde = _dashboardData!['financier']['soldeRestant'] as double;
      final lockOverdue = _dashboardData!['paiements']['lockOverdue'] as bool;
      final DateTime? nextLockAt = _dashboardData!['paiements']['nextLockAt'];
      final dernierPaiement = _dashboardData!['paiements']['dernierPaiement'];

      if (solde > 0 && nextLockAt != null) {
        final now = DateTime.now();

        if (lockOverdue || now.isAfter(nextLockAt)) {
          final diff = now.difference(nextLockAt);
          notificationWidgets.add(
              ListTile(
                leading: const Icon(Icons.lock, color: AppColors.error, size: 28),
                title: Text('Appareil bloqué', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
                subtitle: Text('Retard de paiement de ${_formatDuration(diff)}.', style: TextStyle(color: textSecondary)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 1);
                },
              )
          );
        } else {
          final diff = nextLockAt.difference(now);
          if (diff.inDays <= 3) {
            notificationWidgets.add(
                ListTile(
                  leading: const Icon(Icons.timer, color: AppColors.warning, size: 28),
                  title: Text('Blocage imminent', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Prochain blocage dans ${_formatDuration(diff)}.', style: TextStyle(color: textSecondary)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentIndex = 1);
                  },
                )
            );
          } else {
            notificationWidgets.add(
                ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 28),
                  title: Text('Contrat à jour', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Aucun paiement urgent requis.', style: TextStyle(color: textSecondary)),
                )
            );
          }
        }
      } else if (solde <= 0) {
        notificationWidgets.add(
            ListTile(
              leading: const Icon(Icons.verified, color: AppColors.success, size: 28),
              title: Text('Appareil payé en totalité 🎉', style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold)),
              subtitle: Text('Félicitations, vous n\'avez plus de solde restant !', style: TextStyle(color: textSecondary)),
            )
        );
      }

      if (dernierPaiement != null && dernierPaiement['montant'] > 0) {
        notificationWidgets.add(
            ListTile(
              leading: const Icon(Icons.info_outline, color: AppColors.secondary, size: 28),
              title: Text('Dernier paiement reçu', style: TextStyle(color: textPrimary)),
              subtitle: Text('Un montant de ${dernierPaiement['montant']} \$ a été crédité le ${DateFormat("dd/MM/yyyy 'à' HH:mm", 'fr_FR').format(dernierPaiement['date'])}.', style: TextStyle(color: textSecondary)),
            )
        );
      }
    }

    if (notificationWidgets.isEmpty) {
      notificationWidgets.add(
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Aucune notification pour le moment.', style: TextStyle(color: textSecondary)),
          )
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            Divider(color: inputBorder),
            Expanded(
              child: ListView.separated(
                itemCount: notificationWidgets.length,
                separatorBuilder: (context, index) => Divider(color: inputBorder.withOpacity(0.5)),
                itemBuilder: (context, index) => notificationWidgets[index],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
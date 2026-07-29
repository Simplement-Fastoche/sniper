import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sniper/screens/payment_screen.dart';
import 'package:sniper/screens/profile_screen.dart';
import 'package:sniper/screens/schedule_screen.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';

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
  Map<String, dynamic>? _dashboardData;
  final String _meEndpoint = 'https://admin.sniper-sarl.cloud/api/v1/me';

  @override
  void initState() {
    super.initState();
    _logger = LoggerService();
    _logger.init().then((_) {
      _logger.info('DashboardScreen initialisé');
    });
    _user = User.currentUser();
    _fetchDashboardData();
  }


  Future<void> _fetchDashboardData() async {
    _logger.info('Tentative de chargement du dashboard');
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      if (token == null) {
        _logger.warning('Token manquant, session expirée');
        setState(() {
          _errorMessage = "Session expirée. Veuillez vous reconnecter.";
          _isLoading = false;
        });
        _showError('Session expirée', 'Votre session a expiré. Veuillez vous reconnecter.', onRetry: () => _fetchDashboardData());
        return;
      }

      final response = await http.get(
        Uri.parse(_meEndpoint),
        headers: {
          'Accept': 'application/vnd.api+json', // 👈 CORRECTION : Format strict
          'Authorization': 'Bearer $token',
        },
      );

      _logger.debug('Réponse API /me reçue', data: {'status_code': response.statusCode});

      if (response.statusCode == 200) {
        try {
          final decodedResponse = jsonDecode(response.body);
          final attributes = decodedResponse['data']['attributes'];

          setState(() {
            _dashboardData = _mapApiDataToDashboard(attributes);
            _user = User(
              name: attributes['display_name'] ?? 'Client Inconnu',
              email: 'Client WonyaPay',
              avatarUrl: 'https://ui-avatars.com/api/?name=${attributes['display_name'] ?? 'Client'}&background=6C63FF&color=fff',
              phoneNumber: 'Non renseigné',
              branch: attributes['contract_number'] ?? 'Standard',
            );
            _isLoading = false;
          });
        } catch (e, stackTrace) {
          _logger.error('Erreur lors du décodage', data: {'body': response.body}, error: e, stackTrace: stackTrace);
          setState(() { _errorMessage = "Erreur de traitement des données."; _isLoading = false; });
        }
      } else if (response.statusCode == 429) {
        // 👈 NOUVEAU : Gestion du Rate Limit
        _logger.warning('Rate limit atteint sur /me (429)');
        setState(() {
          _errorMessage = "Trop de requêtes. Veuillez patienter un instant.";
          _isLoading = false;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // 👈 NOUVEAU : Gestion des erreurs d'authentification et de permission
        _logger.warning('Accès refusé', data: {'status': response.statusCode});
        setState(() {
          _errorMessage = "Non autorisé ou accès refusé. Votre session a expiré.";
          _isLoading = false;
        });
      } else {
        _logger.warning('Erreur API', data: {'status': response.statusCode});
        setState(() { _errorMessage = "Erreur serveur (Code: ${response.statusCode})."; _isLoading = false; });
      }
    } catch (e, stackTrace) {
      _logger.error('Erreur réseau Dashboard', error: e, stackTrace: stackTrace);
      setState(() { _errorMessage = "Erreur de connexion au serveur."; _isLoading = false; });
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
    return {
      'client': {
        'nom': apiData['display_name'] ?? 'Client Inconnu',
        'telephone': 'Non renseigné',
      },
      'contrat': {
        'reference': apiData['contract_number'] ?? 'N/A',
        'statut': apiData['status_label'] ?? 'Actif',
      },
      'telephone': {
        'modele': apiData['device_model'] ?? 'Appareil',
        'imei1': apiData['device_imei_suffix'] != null ? '***${apiData['device_imei_suffix']}' : 'N/A',
        'imei2': 'N/A',
        'couleur': '-',
        'stockage': '-',
        'statut': apiData['status_label'] ?? 'Actif',
        'reference_contrat': apiData['contract_number'] ?? 'N/A',
      },
      'financier': {
        'prixTotal': double.tryParse(apiData['total_price_usd'].toString()) ?? 0.0,
        'montantPaye': double.tryParse(apiData['deposit_usd'].toString()) ?? 0.0,
        'soldeRestant': double.tryParse(apiData['balance_usd'].toString()) ?? 0.0,
        'montantJournalier': 0.0,
        'montantHebdomadaire': 0.0,
        'montantMensuel': 0.0,
      },
      'paiements': {
        'prochaineEcheance': apiData['next_installment_due_at'] != null
            ? DateTime.parse(apiData['next_installment_due_at'])
            : DateTime.now().add(const Duration(days: 30)),
        'retard': 0,
        'dernierPaiement': {
          'date': DateTime.now(),
          'montant': double.tryParse(apiData['deposit_usd'].toString()) ?? 0.0,
          'methode': 'Mobile Money',
        },
      },
      'payTrigger': {
        'etat': apiData['status_label'] ?? 'Actif',
        'dateTrigger': apiData['next_installment_due_at'] != null
            ? DateTime.parse(apiData['next_installment_due_at'])
            : DateTime.now(),
        'montantTrigger': double.tryParse(apiData['balance_usd'].toString()) ?? 0.0,
      },
      'actionsAutorisees': [
        'Effectuer un paiement',
        'Voir les détails du contrat',
        'Contacter le support',
        'Signaler un problème',
      ],
    };
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: Icon(
                    Icons.menu,
                    color: Colors.white.withOpacity(0.9),
                    size: 26,
                  ),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: Text(
                _getAppBarTitle(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  shadows: [
                    Shadow(
                      color: Color(0xFF6C63FF),
                      blurRadius: 15,
                    ),
                    Shadow(
                      color: Color(0xFF6C63FF),
                      blurRadius: 30,
                    ),
                  ],
                ),
              ),
              actions: [
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_outlined,
                        color: Colors.white.withOpacity(0.9),
                        size: 26,
                      ),
                      onPressed: () => _showNotifications(context),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B6B), Color(0xFFFF4444)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6B6B).withOpacity(0.6),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              iconTheme: IconThemeData(
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
        ),
      ),
      drawer: CustomDrawer(
        user: _user,
        onMenuItemSelected: (index) {
          Navigator.pop(context);
          debugPrint('Menu item selected: $index');
        },
      ),
      body: _buildSelectedTab(),
      bottomNavigationBar: SafeArea(
        child: CustomBottomNav(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }
  Widget _buildSelectedTab() {
    switch (_currentIndex) {
      case 0:
        return _buildDashboardContent();
      case 1:
        return const PaymentScreen();
      case 2:
        return const ScheduleScreen();
      case 3:
        return const HistoryScreen();
      case 4:
        return _dashboardData != null
            ? ProfileScreen(dashboardData: _dashboardData!)
            : const Center(child: CircularProgressIndicator());
      default:
        return _buildDashboardContent();
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

  Widget _buildDashboardContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 100),
          child: CircularProgressIndicator(
            color: Color(0xFF6C63FF),
            strokeWidth: 3,
          ),
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 100),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(fontSize: 16, color: Colors.white)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchDashboardData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Réessayer'),
              )
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _buildPhoneContractCard(),
                const SizedBox(height: 14),
                _buildFinancialCard(),
                const SizedBox(height: 14),
                _buildPayTriggerCard(),
                const SizedBox(height: 14),

              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== DESIGN 2: NEON GLOW ====================

  // Carte avec effet néon
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
            color: glowColor.withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: glowColor.withOpacity(0.1),
            blurRadius: 60,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _buildPhoneContractCard() {
    final telephone = _dashboardData!['telephone'];

    String maskImei(String imei) {
      if (imei.length <= 8) return imei;
      return '${imei.substring(0, 4)}****${imei.substring(imei.length - 4)}';
    }

    return _buildNeonCard(
      glowColor: const Color(0xFF6C63FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3F3D9E)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(Icons.phone_android, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      telephone['modele'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Color(0xFF6C63FF),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF4CAF50),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          telephone['statut'],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3F3D9E)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  'Ref: ${telephone['reference_contrat']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNeonDetail('Modèle', telephone['modele']),
                _buildNeonDivider(),
                _buildNeonDetail('Stockage', telephone['stockage']),
                _buildNeonDivider(),
                _buildNeonDetail('Couleur', telephone['couleur']),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF6C63FF).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code, color: Color(0xFF6C63FF), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('IMEI 1', style: TextStyle(color: Colors.white60, fontSize: 9)),
                            Text(
                              maskImei(telephone['imei1']),
                              style: const TextStyle(
                                color: Colors.white,
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
                Container(width: 1, height: 28, color: Colors.white.withOpacity(0.1)),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code, color: Color(0xFF6C63FF), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('IMEI 2', style: TextStyle(color: Colors.white60, fontSize: 9)),
                            Text(
                              maskImei(telephone['imei2']),
                              style: const TextStyle(
                                color: Colors.white,
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

  Widget _buildNeonDetail(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildNeonDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withOpacity(0.1),
    );
  }

  Widget _buildFinancialCard() {
    final financier = _dashboardData!['financier'];
    final paiements = _dashboardData!['paiements'];
    final prochaineEcheance = paiements['prochaineEcheance'] as DateTime;
    final dernierPaiement = paiements['dernierPaiement'];

    return _buildNeonCard(
      glowColor: const Color(0xFF00D4FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.attach_money, color: Color(0xFF00D4FF), size: 22),
              SizedBox(width: 10),
              Text(
                'Finances',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Color(0xFF00D4FF),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildNeonFinancialItem(
                  label: 'Total',
                  value: '${financier['prixTotal']} USD',
                  color: const Color(0xFF00D4FF),
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white.withOpacity(0.1)),
              Expanded(
                child: _buildNeonFinancialItem(
                  label: 'Payé',
                  value: '${financier['montantPaye']} USD',
                  color: const Color(0xFF4CAF50),
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white.withOpacity(0.1)),
              Expanded(
                child: _buildNeonFinancialItem(
                  label: 'Solde',
                  value: '${financier['soldeRestant']} USD',
                  color: const Color(0xFFFF6B6B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF00D4FF).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Color(0xFF00D4FF), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Prochaine échéance', style: TextStyle(color: Colors.white60, fontSize: 10)),
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(prochaineEcheance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF4CAF50).withOpacity(0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4CAF50).withOpacity(0.2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Text(
                        'À jour',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.payment, color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Dernier paiement', style: TextStyle(color: Colors.white60, fontSize: 10)),
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(dernierPaiement['date'])} - ${dernierPaiement['montant']} USD',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF00D4FF).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        dernierPaiement['methode'],
                        style: const TextStyle(
                          color: Color(0xFF00D4FF),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildNeonSmallItem('Journalier', '${financier['montantJournalier']} USD')),
              const SizedBox(width: 8),
              Expanded(child: _buildNeonSmallItem('Hebdo', '${financier['montantHebdomadaire']} USD')),
              const SizedBox(width: 8),
              Expanded(child: _buildNeonSmallItem('Mensuel', '${financier['montantMensuel']} USD')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNeonFinancialItem({required String label, required String value, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
            shadows: [
              Shadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNeonSmallItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00D4FF).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00D4FF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayTriggerCard() {
    final payTrigger = _dashboardData!['payTrigger'];

    return _buildNeonCard(
      glowColor: const Color(0xFFFF6B6B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Color(0xFFFF6B6B), size: 22),
              SizedBox(width: 10),
              Text(
                'PayTrigger',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Color(0xFFFF6B6B),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFF6B6B).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFFF6B6B), size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('État', style: TextStyle(color: Colors.white60, fontSize: 10)),
                      Text(
                        payTrigger['etat'],
                        style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Color(0xFFFF6B6B),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF6B6B).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(payTrigger['dateTrigger']),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFF6B6B).withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_money, color: Color(0xFFFF6B6B), size: 18),
                const SizedBox(width: 12),
                const Text('Seuil:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const Spacer(),
                Text(
                  '${payTrigger['montantTrigger']} USD',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B6B),
                    shadows: [
                      Shadow(
                        color: Color(0xFFFF6B6B),
                        blurRadius: 8,
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


  Widget _buildNeonActionButton(String label) {
    IconData icon;
    Color color;

    switch (label) {
      case 'Effectuer un paiement':
        icon = Icons.payment;
        color = const Color(0xFF6C63FF);
        break;
      case 'Voir les détails du contrat':
        icon = Icons.description;
        color = const Color(0xFF00D4FF);
        break;
      case 'Contacter le support':
        icon = Icons.support_agent;
        color = const Color(0xFF4CAF50);
        break;
      case 'Signaler un problème':
        icon = Icons.warning;
        color = const Color(0xFFFF6B6B);
        break;
      default:
        icon = Icons.arrow_forward;
        color = Colors.grey;
    }

    return InkWell(
      onTap: () => _handleAction(label),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.15),
              color.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 15,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_ios,
                color: color,
                size: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(String action) {
    debugPrint('Action sélectionnée: $action');
    switch (action) {
      case 'Effectuer un paiement':
        setState(() => _currentIndex = 1);
        break;
      case 'Voir les détails du contrat':
        break;
      case 'Contacter le support':
        break;
      case 'Signaler un problème':
        break;
    }
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Color(0xFF00D4FF)),
                    title: const Text('Votre paiement a été reçu', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Il y a 2 heures', style: TextStyle(color: Colors.white60)),
                    trailing: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00D4FF),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF00D4FF),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.warning, color: Color(0xFFFF6B6B)),
                    title: const Text('Paiement en retard', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Il y a 1 jour', style: TextStyle(color: Colors.white60)),
                    trailing: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6B6B),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFFF6B6B),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
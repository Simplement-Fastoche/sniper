import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'activation_screen.dart'; // Assure-toi que le chemin est correct

class ProfileScreen extends StatelessWidget {
  final Map<String, dynamic> dashboardData;

  const ProfileScreen({
    super.key,
    required this.dashboardData,
  });

  Future<void> _logout(BuildContext context) async {
    // Demande de confirmation avant de déconnecter
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter de cet appareil ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Se déconnecter', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Suppression du token
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      // Note : On ne supprime PAS 'installation_id' car l'appareil physique reste le même.

      // 2. Redirection vers l'écran d'activation
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const ActivationScreen()),
              (Route<dynamic> route) => false, // Supprime tout l'historique de navigation
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = dashboardData['client'];
    final contrat = dashboardData['contrat'];

    return Container(
      color: const Color(0xFFF8F9FC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- EN-TÊTE DU PROFIL ---
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF4361EE).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF4361EE), width: 2),
                ),
                child: const Icon(Icons.person, size: 50, color: Color(0xFF4361EE)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              client['nom'],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1E2B)),
            ),
            const SizedBox(height: 4),
            Text(
              client['telephone'],
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // --- INFORMATIONS DU COMPTE ---
            _buildSectionHeader('Informations du compte'),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  _buildListTile(Icons.badge, 'Nom complet', client['nom']),
                  const Divider(height: 1),
                  _buildListTile(Icons.phone, 'Numéro de téléphone', client['telephone']),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- DÉTAILS DU CONTRAT ---
            _buildSectionHeader('Détails du contrat'),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  _buildListTile(Icons.description, 'Référence', contrat['reference']),
                  const Divider(height: 1),
                  _buildListTile(Icons.verified_user, 'Statut', contrat['statut'], isStatus: true),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- BOUTON DÉCONNEXION ---
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title, String subtitle, {bool isStatus = false}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4361EE).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF4361EE), size: 20),
      ),
      title: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      subtitle: isStatus
          ? Row(
        children: [
          Text(subtitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
        ],
      )
          : Text(subtitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1E2B))),
    );
  }
}
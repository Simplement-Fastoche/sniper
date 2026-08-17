import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sniper/models/user_model.dart';
import '../config/app_colors.dart';

class CustomDrawer extends StatelessWidget {
  final User user;
  final Function(int) onMenuItemSelected;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;

  const CustomDrawer({
    super.key,
    required this.user,
    required this.onMenuItemSelected,
    this.isDarkMode = false,
    required this.onThemeToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF1A1A2E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1A1E2B);
    final textSecondary = isDarkMode ? Colors.white70 : Colors.black54;

    return Drawer(
      backgroundColor: bgColor,
      width: MediaQuery.of(context).size.width * 0.85,
      child: Column(
        children: [
          // Header premium avec profil utilisateur
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    ? [
                  const Color(0xFF0A0A1A),
                  const Color(0xFF1A2A1A),
                  const Color(0xFF00A83A).withOpacity(0.8),
                ]
                    : [
                  const Color(0xFF1A1E2B),
                  const Color(0xFF004D1A),
                  const Color(0xFF00A83A).withOpacity(0.9),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Ligne avec Avatar à gauche et infos à droite
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar avec effet de glow
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00A83A).withOpacity(0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white,
                            child: FutureBuilder<SharedPreferences>(
                                future: SharedPreferences.getInstance(),
                                builder: (context, snapshot) {
                                  Map<String, String>? imageHeaders;

                                  if (snapshot.hasData) {
                                    final token = snapshot.data!.getString('auth_token');
                                    if (token != null && !user.avatarUrl.contains('ui-avatars.com')) {
                                      imageHeaders = {
                                        'Authorization': 'Bearer $token',
                                        'Accept': 'application/vnd.api+json'
                                      };
                                    }
                                  }

                                  return CircleAvatar(
                                    radius: 36,
                                    backgroundColor: Colors.grey[200],
                                    backgroundImage: NetworkImage(
                                      user.avatarUrl,
                                      headers: imageHeaders,
                                    ),
                                    onBackgroundImageError: (error, stackTrace) {
                                      debugPrint('Erreur de chargement de l\'image de profil: $error');
                                    },
                                  );
                                }
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFC107),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Informations à droite de la photo
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Nom du client
                          Text(
                            user.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Affichage du Numéro de téléphone
                          Row(
                            children: [
                              Icon(Icons.phone_android, color: Colors.white.withOpacity(0.7), size: 12),
                              const SizedBox(width: 4),
                              Text(
                                user.phoneNumber,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Contrat
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.2),
                                  Colors.white.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),
                            child: Text(
                              'N° Contrat: ${user.branch}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Bouton Voir les détails
                Center(
                  child: Container(
                    width: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.2),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => onMenuItemSelected(-1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),

                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ===== SEPARATEUR =====
          const SizedBox(height: 8),

          // ===== ITEMS DU MENU =====
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [

                const Divider(color: Colors.grey, height: 30),

                // ===== TOGGLE THEME =====
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isDarkMode ? Icons.light_mode : Icons.dark_mode,
                          color: isDarkMode ? AppColors.secondary : AppColors.primary,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        isDarkMode ? 'Thème clair' : 'Thème sombre',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                      trailing: Switch(
                        value: isDarkMode,
                        onChanged: (_) => onThemeToggle(),
                        activeColor: AppColors.primary,
                        activeTrackColor: AppColors.primaryLight,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey[300],
                      ),
                      onTap: onThemeToggle,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hoverColor: AppColors.primary.withOpacity(0.05),
                      splashColor: AppColors.primary.withOpacity(0.1),
                    ),
                  ),
                ),

                const Divider(color: Colors.grey, height: 20),
              ],
            ),
          ),


        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required int index,
    Color? iconColor,
    Color? textColor,
    required bool isDarkMode,
  }) {
    final defaultColor = isDarkMode ? Colors.white70 : const Color(0xFF1A1E2B);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor != null
                  ? iconColor.withOpacity(0.1)
                  : AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppColors.primary,
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: textColor ?? defaultColor,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.3,
            ),
          ),
          onTap: () => onMenuItemSelected(index),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          hoverColor: AppColors.primary.withOpacity(0.05),
          splashColor: AppColors.primary.withOpacity(0.1),
        ),
      ),
    );
  }
}
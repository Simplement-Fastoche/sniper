import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../config/app_colors.dart';

class UpdateScreen extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;
  final bool isMandatory;
  final String versionName;
  final int sizeBytes;

  const UpdateScreen({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    required this.isMandatory,
    required this.versionName,
    required this.sizeBytes,
  });

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _downloadStatus = "Initialisation...";

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Convertit les octets en Mo lisibles
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    final double mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _downloadStatus = "Connexion au serveur sécurisé...";
    });

    try {
      final request = http.Request('GET', Uri.parse(widget.updateUrl));
      final response = await http.Client().send(request);
      final totalBytes = response.contentLength ?? widget.sizeBytes;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/update_${widget.versionName}.apk');
      final sink = file.openWrite();

      int downloadedBytes = 0;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          setState(() {
            _progress = downloadedBytes / totalBytes;
            _downloadStatus = "Téléchargement en cours : ${(_progress * 100).toStringAsFixed(0)}%";
          });
        }
      });

      await sink.close();

      setState(() {
        _progress = 1.0;
        _downloadStatus = "Lancement de l'installation système...";
      });

      await Future.delayed(const Duration(milliseconds: 800));

      final result = await OpenFilex.open(file.path);

      if (result.type != ResultType.done) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = "Action requise : Veuillez autoriser l'installation.";
        });
      }
    } catch (e) {
      debugPrint("Erreur de téléchargement : $e");
      setState(() {
        _isDownloading = false;
        _downloadStatus = "Échec du téléchargement. Vérifiez votre connexion.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedSize = _formatFileSize(widget.sizeBytes);

    return PopScope(
      canPop: !widget.isMandatory && !_isDownloading,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Icône animée au centre
                AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1 + (_pulseController.value * 0.1)),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.2 * _pulseController.value),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.system_update_rounded,
                          size: 64,
                          color: AppColors.primary,
                        ),
                      );
                    }
                ),
                const SizedBox(height: 32),

                // Titre
                Text(
                  widget.isMandatory ? "Mise à jour requise" : "Mise à jour disponible",
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Badge de version et de taille (Style pilule premium)
                if (widget.versionName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF3D3D5C)),
                    ),
                    child: Text(
                      'Version ${widget.versionName} ${formattedSize.isNotEmpty ? " • $formattedSize" : ""}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Description textuelle
                Text(
                  widget.isMandatory
                      ? "Votre application nécessite une mise à jour de sécurité vitale pour continuer à fonctionner."
                      : "Une nouvelle version avec des optimisations et de nouvelles fonctionnalités est prête.",
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFA0AEC0),
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Notes de version stylisées (Glassmorphism)
                if (widget.releaseNotes.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
                            SizedBox(width: 10),
                            Text(
                              "Quoi de neuf ?",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.releaseNotes,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),

                // 👇 ZONE DYNAMIQUE : Barre de progression Premium
                if (_isDownloading)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _downloadStatus,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              "${(_progress * 100).toStringAsFixed(0)}%",
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progress,
                            backgroundColor: const Color(0xFF1E1E2E),
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                // Bouton de téléchargement premium
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _startDownloadAndInstall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_download_rounded, size: 22),
                          SizedBox(width: 12),
                          Text(
                            "Installer la mise à jour",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bouton "Plus tard" si facultatif
                if (!widget.isMandatory && !_isDownloading) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Plus tard",
                      style: TextStyle(
                          color: Color(0xFFA0AEC0),
                          fontSize: 15,
                          fontWeight: FontWeight.w600
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const SizedBox(height: 50),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
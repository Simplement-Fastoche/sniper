import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

class ErrorPopupWidget extends StatefulWidget {
  final String title;
  final String message;
  final Map<String, dynamic>? details;
  final VoidCallback? onRetry;
  final bool showAllLogs; // NOUVEAU

  const ErrorPopupWidget({
    Key? key,
    required this.title,
    required this.message,
    this.details,
    this.onRetry,
    this.showAllLogs = false, // Par défaut false
  }) : super(key: key);

  @override
  State<ErrorPopupWidget> createState() => _ErrorPopupWidgetState();

  static void showErrorDialog(
      BuildContext context, {
        required String title,
        required String message,
        Map<String, dynamic>? details,
        VoidCallback? onRetry,
        bool showAllLogs = false,
      }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return ErrorPopupWidget(
          title: title,
          message: message,
          details: details,
          onRetry: onRetry,
          showAllLogs: showAllLogs,
        );
      },
    );
  }
}

class _ErrorPopupWidgetState extends State<ErrorPopupWidget> {
  bool _showDetails = false;
  bool _showAllLogs = false;
  List<LogEntry> _allLogs = [];
  bool _isLoadingLogs = false;
  final LoggerService _logger = LoggerService();

  @override
  void initState() {
    super.initState();
    if (widget.showAllLogs) {
      _loadAllLogs();
    }
  }

  Future<void> _loadAllLogs() async {
    setState(() => _isLoadingLogs = true);
    await _logger.init();
    _allLogs = _logger.getLogs(limit: 50); // Derniers 50 logs
    setState(() => _isLoadingLogs = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec titre

            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Logs récents:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // ✅ NOUVEAU BOUTON : TOUT COPIER
                if (_allLogs.isNotEmpty)
                  TextButton.icon(
                    onPressed: _copyAllLogs,
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('Tout copier', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                const SizedBox(width: 4),
                if (widget.onRetry != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onRetry!();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4361EE),
                      minimumSize: const Size(80, 30),
                    ),
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                    label: const Text('Réessayer', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Fermer',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            // Message d'erreur
            Text(
              widget.message,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            if (widget.details != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  setState(() {
                    _showDetails = !_showDetails;
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _showDetails ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showDetails ? 'Cacher les détails' : 'Voir les détails',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showDetails)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Détails de l\'erreur:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...widget.details!.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${entry.key}: ',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              final copyText = '''
Titre: ${widget.title}
Message: ${widget.message}
Détails: ${jsonEncode(widget.details)}
Timestamp: ${DateTime.now().toIso8601String()}
''';
                              Clipboard.setData(ClipboardData(text: copyText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Erreur copiée dans le presse-papier'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            tooltip: 'Copier l\'erreur',
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Copier l\'erreur',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
            // AFFICHER TOUS LES LOGS
            const Divider(),
            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Logs récents:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (widget.onRetry != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onRetry!();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4361EE),
                      minimumSize: const Size(80, 30),
                    ),
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                    label: const Text('Réessayer', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Fermer',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Liste des logs
            Expanded(
              child: _isLoadingLogs
                  ? const Center(child: CircularProgressIndicator())
                  : _allLogs.isEmpty
                  ? const Center(
                child: Text(
                  'Aucun log disponible',
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: _allLogs.length,
                itemBuilder: (context, index) {
                  final log = _allLogs[index];
                  return _buildLogItem(log);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      elevation: 1,
      child: InkWell(
        onTap: () => _showLogDetails(log),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getIconForLevel(log.level),
                    color: log.level.color,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      log.message,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: log.level.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.level.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: log.level.color,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                log.timestamp.toLocal().toString().substring(0, 19),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
              if (log.data != null)
                Text(
                  log.data!.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }


  void _copyAllLogs() {
    if (_allLogs.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('=== LOGS DE L\'APPLICATION ===');
    buffer.writeln('Date: ${DateTime.now().toLocal()}');
    buffer.writeln('Total: ${_allLogs.length} logs');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (var log in _allLogs.reversed) {
      buffer.writeln('[${log.level.name.toUpperCase()}] ${log.timestamp.toLocal()}');
      buffer.writeln('  Message: ${log.message}');
      if (log.data != null) {
        buffer.writeln('  Données: ${jsonEncode(log.data)}');
      }
      buffer.writeln('-' * 50);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Tous les logs copiés dans le presse-papier'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  void _showLogDetails(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getIconForLevel(log.level), color: log.level.color),
            const SizedBox(width: 8),
            Text('Détails du log', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Niveau: ${log.level.name.toUpperCase()}',
                  style: TextStyle(
                    color: log.level.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Timestamp: ${log.timestamp.toLocal()}'),
                const SizedBox(height: 8),
                Text('Message: ${log.message}'),
                if (log.data != null) ...[
                  const Divider(),
                  const Text(
                    'Données:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(log.data),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final text = '''
=== LOG DÉTAILLÉ ===
Niveau: ${log.level.name}
Timestamp: ${log.timestamp.toLocal()}
Message: ${log.message}
Données: ${jsonEncode(log.data)}
===================
''';
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Log copié dans le presse-papier'),
                    duration: Duration(seconds: 2),
                  ),
                );
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copier'),
          ),
        ],
      ),
    );
  }

  IconData _getIconForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warning:
        return Icons.warning_amber_outlined;
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.debug:
        return Icons.bug_report_outlined;
    }
  }
}
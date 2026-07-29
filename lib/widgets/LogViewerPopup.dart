// widgets/log_viewer_popup.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

class LogViewerPopup extends StatefulWidget {
  const LogViewerPopup({super.key});

  @override
  State<LogViewerPopup> createState() => _LogViewerPopupState();

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return const LogViewerPopup();
      },
    );
  }
}

class _LogViewerPopupState extends State<LogViewerPopup> {
  final LoggerService _logger = LoggerService();
  List<LogEntry> _logs = [];
  bool _isLoading = true;
  LogLevel? _filterLevel;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    await _logger.init();
    _logs = _logger.getLogs(level: _filterLevel);
    setState(() => _isLoading = false);
  }

  Future<void> _clearLogs() async {
    await _logger.clearLogs();
    _loadLogs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs effacés'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // En-tête
            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                const Text(
                  '📋 Logs détaillés',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Compteur de logs
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_logs.length} logs',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            // Barre d'outils
            Row(
              children: [
                // Filtre par niveau
                DropdownButton<LogLevel?>(
                  value: _filterLevel,
                  hint: const Text('Filtre'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    const DropdownMenuItem(value: LogLevel.info, child: Text('ℹ️ Info')),
                    const DropdownMenuItem(value: LogLevel.warning, child: Text('⚠️ Warning')),
                    const DropdownMenuItem(value: LogLevel.error, child: Text('❌ Error')),
                    const DropdownMenuItem(value: LogLevel.debug, child: Text('🐛 Debug')),
                  ],
                  onChanged: (level) {
                    setState(() {
                      _filterLevel = level;
                      _loadLogs();
                    });
                  },
                ),
                const SizedBox(width: 8),
                // Bouton effacer
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.red),
                  onPressed: _clearLogs,
                  tooltip: 'Effacer tous les logs',
                ),
                const SizedBox(width: 8),
                // Bouton exporter
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.blue),
                  onPressed: () => _exportLogs(),
                  tooltip: 'Partager les logs',
                ),
                const Spacer(),
                // Bouton refresh
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.green),
                  onPressed: _loadLogs,
                  tooltip: 'Rafraîchir',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Liste des logs
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _logs.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Aucun log disponible', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      child: InkWell(
        onTap: () => _showLogDetails(log),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getIconForLevel(log.level),
                    color: log.level.color,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.message,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: log.level.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      log.level.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: log.level.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${log.timestamp.toLocal().toString().substring(0, 19)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              if (log.data != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.data!.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
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
            Text('Détails du log', style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: log.level.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        log.level.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: log.level.color,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      log.timestamp.toLocal().toString(),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const Divider(),
                const Text(
                  'Message:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(log.message),
                const SizedBox(height: 12),
                if (log.data != null) ...[
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
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(log.data),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
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

  Future<void> _exportLogs() async {
    try {
      await _logger.init();
      final logs = await _logger.exportLogs();
      await Clipboard.setData(ClipboardData(text: logs));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tous les logs copiés dans le presse-papier'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export: $e')),
        );
      }
    }
  }
}
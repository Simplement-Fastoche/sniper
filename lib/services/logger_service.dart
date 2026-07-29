import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  static const String _logFileName = 'app_logs.txt';
  static const int _maxLogEntries = 1000;

  List<LogEntry> _logs = [];
  bool _initialized = false;
  String? _logFilePath;

  Future<void> init() async {
    if (_initialized) return;

    try {
      // Essayer d'abord le stockage externe (accessible via gestionnaire de fichiers)
      await _initExternalStorage();
    } catch (e) {
      debugPrint('Erreur init stockage externe: $e');
      // Fallback sur le stockage interne
      await _initInternalStorage();
    }

    await _loadLogs();
    _initialized = true;
  }

  // Dans logger_service.dart, ajoutez cette méthode :
  String getAllLogsFormatted() {
    if (_logs.isEmpty) return 'Aucun log disponible';

    final buffer = StringBuffer();
    buffer.writeln('=== LOGS DE L\'APPLICATION ===');
    buffer.writeln('Total: ${_logs.length} logs');
    buffer.writeln('Date: ${DateTime.now().toLocal()}');
    buffer.writeln('=' * 40);
    buffer.writeln();

    for (var log in _logs.reversed) {
      buffer.writeln('[${log.level.name.toUpperCase()}] ${log.timestamp.toLocal()}');
      buffer.writeln('  Message: ${log.message}');
      if (log.data != null) {
        buffer.writeln('  Données: ${jsonEncode(log.data)}');
      }
      buffer.writeln('-' * 40);
    }

    return buffer.toString();
  }


  Future<void> _initExternalStorage() async {
    try {
      // Demander la permission de stockage (pour Android)
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          debugPrint('Permission de stockage refusée, utilisation du stockage interne');
          throw Exception('Permission refusée');
        }
      }

      // Utiliser le dossier Downloads (toujours accessible sans root)
      final directory = Directory('/storage/emulated/0/Download/SniperLogs');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      _logFilePath = '${directory.path}/$_logFileName';
      debugPrint('Logs dans: $_logFilePath');
    } catch (e) {
      debugPrint('Erreur init externe: $e');
      rethrow;
    }
  }

  Future<void> _initInternalStorage() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFilePath = '${directory.path}/$_logFileName';
    debugPrint('Logs internes dans: $_logFilePath');
  }

  Future<void> _loadLogs() async {
    try {
      if (_logFilePath == null) return;

      final file = File(_logFilePath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n').where((line) => line.isNotEmpty);
        _logs = lines.map((line) {
          try {
            return LogEntry.fromJson(jsonDecode(line));
          } catch (e) {
            return LogEntry(
              timestamp: DateTime.now(),
              level: LogLevel.error,
              message: 'Erreur de parsing: $line',
              data: {'error': e.toString()},
            );
          }
        }).toList();
      }
    } catch (e) {
      debugPrint('Erreur chargement logs: $e');
    }
  }

  Future<void> _saveLogs() async {
    try {
      if (_logFilePath == null) return;

      final file = File(_logFilePath!);
      // Créer le dossier si nécessaire
      await file.parent.create(recursive: true);

      final content = _logs.map((log) => jsonEncode(log.toJson())).join('\n');
      await file.writeAsString(content);
      debugPrint('Logs sauvegardés: $_logFilePath');
    } catch (e) {
      debugPrint('Erreur sauvegarde logs: $e');
    }
  }

  // Ajouter un log avec différents niveaux
  void info(String message, {Map<String, dynamic>? data}) {
    _addLog(LogLevel.info, message, data);
  }

  void warning(String message, {Map<String, dynamic>? data}) {
    _addLog(LogLevel.warning, message, data);
  }

  void error(String message, {Map<String, dynamic>? data, dynamic error, StackTrace? stackTrace}) {
    final fullData = Map<String, dynamic>.from(data ?? {});
    if (error != null) {
      fullData['error'] = error.toString();
    }
    if (stackTrace != null) {
      fullData['stackTrace'] = stackTrace.toString();
    }
    _addLog(LogLevel.error, message, fullData);
  }

  void debug(String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      _addLog(LogLevel.debug, message, data);
    }
  }

  void _addLog(LogLevel level, String message, Map<String, dynamic>? data) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      data: data,
    );

    _logs.add(entry);
    if (_logs.length > _maxLogEntries) {
      _logs.removeAt(0);
    }

    _saveLogs();

    // Afficher dans la console si en debug
    if (kDebugMode) {
      debugPrint('[${level.name.toUpperCase()}] $message');
      if (data != null) {
        debugPrint('Données: $data');
      }
    }
  }

  List<LogEntry> getLogs({LogLevel? level, int? limit}) {
    var filtered = _logs;
    if (level != null) {
      filtered = filtered.where((log) => log.level == level).toList();
    }
    if (limit != null && limit > 0) {
      filtered = filtered.reversed.take(limit).toList().reversed.toList();
    }
    return filtered;
  }

  Future<void> clearLogs() async {
    _logs.clear();
    await _saveLogs();
  }

  Future<String> exportLogs() async {
    return _logs.map((log) {
      final json = log.toJson();
      return '${DateTime.now().toIso8601String()} | ${log.level.name} | ${log.message} | ${jsonEncode(log.data)}';
    }).join('\n');
  }

  String getLogFilePath() => _logFilePath ?? 'Non disponible';
}

enum LogLevel {
  info,
  warning,
  error,
  debug,
}

extension LogLevelExtension on LogLevel {
  String get name {
    switch (this) {
      case LogLevel.info:
        return 'info';
      case LogLevel.warning:
        return 'warning';
      case LogLevel.error:
        return 'error';
      case LogLevel.debug:
        return 'debug';
    }
  }

  Color get color {
    switch (this) {
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.debug:
        return Colors.grey;
    }
  }
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final Map<String, dynamic>? data;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.data,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      'data': data,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      level: LogLevel.values.firstWhere(
            (e) => e.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      message: json['message'],
      data: json['data'],
    );
  }
}
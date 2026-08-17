import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const String _keyToken = 'secure_auth_token';
  static const String _keyInstallationId = 'secure_installation_id';

  // Sauvegarder dans le coffre-fort (Crytpé par l'OS)
  static Future<void> saveSecureData(String token, String installationId) async {
    try {
      await _storage.write(key: _keyToken, value: token);
      await _storage.write(key: _keyInstallationId, value: installationId);
      debugPrint('✅ Token sécurisé dans le Keystore');
    } catch (e) {
      debugPrint('❌ Erreur de sauvegarde sécurisée: $e');
    }
  }

  // Récupérer depuis le coffre-fort
  static Future<Map<String, String>?> getSecureData() async {
    try {
      final token = await _storage.read(key: _keyToken);
      final installationId = await _storage.read(key: _keyInstallationId);

      if (token != null && installationId != null) {
        debugPrint('✅ Token récupéré depuis le Keystore (Survie au Clear Data !)');
        return {
          'token': token,
          'installation_id': installationId,
        };
      }
    } catch (e) {
      debugPrint('❌ Erreur de lecture sécurisée: $e');
    }
    return null;
  }
}
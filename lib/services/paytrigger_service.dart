import 'dart:convert';
import 'package:http/http.dart' as http;
// 👇 1. NOUVEL IMPORT POUR TA CONFIGURATION CENTRALE
import '../config/api_config.dart';

class PayTriggerService {
  static Future<void> sendCallback({required bool isQuarantined}) async {
    try {
      final response = await http.post(
        // 👇 2. UTILISATION DE LA CONFIGURATION CENTRALE
        Uri.parse(ApiConfig.payTriggerCallbackEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Attention: s'il faut un token, n'oublie pas de l'ajouter ici
        },
        body: jsonEncode({
          "code": 200,
          "quarantined": isQuarantined
        }),
      );

      if (response.statusCode == 200) {
        print("Synchronisation PayTrigger réussie.");
      } else {
        print("Erreur PayTrigger: ${response.body}");
      }
    } catch (e) {
      print("Erreur réseau lors de la synchronisation PayTrigger: $e");
    }
  }
}
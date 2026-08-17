// lib/config/api_config.dart
class ApiConfig {
  static const bool isProduction = true;

  static const String _domainTest = 'https://admin.sniper-sarl.cloud';
  static const String _domainProd = 'https://admin.sniper-sarl.com';

  static String get domain => isProduction ? _domainProd : _domainTest;

  static String get baseUrl => '$domain/api/v1';

  static String get activateEndpoint => '$baseUrl/auth/activate';
  static String get meEndpoint => '$baseUrl/me';

  // CORRECTIONS ICI 👇
  static String get paymentsEndpoint => '$baseUrl/payments';
  static String get quoteEndpoint => '$baseUrl/payment-quotes'; // <-- Suppression du /device/

  // Plus besoin de devicePaymentsEndpoint, on utilise paymentsEndpoint
  // static String get devicePaymentsEndpoint => '$baseUrl/device/payments';
  static String get scheduleEndpoint => '$baseUrl/schedule';

  static String get payTriggerCallbackEndpoint => '$domain/api/paytrigger/callback';

  static const String fallbackAvatarUrl = 'https://ui-avatars.com/api/';
}
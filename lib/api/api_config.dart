import '../services/config_service.dart';

class ApiConfig {
  static Future<String> get authUrl async {
    final baseUrl = await ConfigService.getBaseUrl();
        if (baseUrl == null || baseUrl.isEmpty) {
          throw Exception(
            'Base URL não configurada. Abra a tela de Configurações e informe o endereço do servidor.'
          );
        }
    return '$baseUrl/cisspoder-auth/oauth/token';
  }

  static Future<String> serviceUrl(String service) async {
    final baseUrl = await ConfigService.getBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception(
          'Base URL não configurada. Abra a tela de Configurações e informe o endereço do servidor.'
      );
    }
    return '$baseUrl/cisspoder-service/$service';
  }
}
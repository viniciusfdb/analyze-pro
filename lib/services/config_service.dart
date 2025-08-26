import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_service.dart';

class ConfigService {
  // Recupera a URL base armazenada
  static Future<String?> getBaseUrl() async {
    return await SecureStorageService.getBaseUrl();
  }

  // Salva a URL, o nome de usuário e a senha (salvamento definitivo)
  static Future<bool> saveConfig(String baseUrl, String username, String password) async {
    try {
      await SecureStorageService.saveBaseUrl(baseUrl);
      await SecureStorageService.saveUsername(username);
      await SecureStorageService.savePassword(password);
      return true;
    } catch (e) {
      print("Erro ao salvar configurações: $e");
      return false;
    }
  }
  static Future<void> clearTempConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tempBaseUrl');
    await prefs.remove('tempUsername');
    await prefs.remove('tempPassword');
  }
  // Salva temporariamente as configurações (apenas para validação, sem confirmar como "válido")
  static Future<void> saveTempConfig(String baseUrl, String username, String password) async {
    // Usa as mesmas funções do armazenamento seguro, mas a lógica de validação controlará o uso
    await SecureStorageService.saveBaseUrl(baseUrl);
    await SecureStorageService.saveUsername(username);
    await SecureStorageService.savePassword(password);
  }
}
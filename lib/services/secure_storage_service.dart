import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final _storage = FlutterSecureStorage();
  static const _baseUrlKey = 'base_url';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';
  static const _tokenKey = 'auth_token';

  // 🔹 Base URL
  static Future<void> saveBaseUrl(String baseUrl) async {
    // Garantir que a URL tenha o prefixo adequado
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';  // Adiciona 'http://' se não estiver presente
    }
    await _storage.write(key: _baseUrlKey, value: baseUrl);
  }

  static Future<String?> getBaseUrl() async {
    return await _storage.read(key: _baseUrlKey);
  }

  // 🔹 Usuário
  static Future<void> saveUsername(String username) async {
    await _storage.write(key: _usernameKey, value: username);
  }

  static Future<String?> getUsername() async {
    return await _storage.read(key: _usernameKey);
  }

  // 🔹 Senha
  static Future<void> savePassword(String password) async {
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<String?> getPassword() async {
    return await _storage.read(key: _passwordKey);
  }

  // 🔹 Token
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }

  // 🔹 Limpa todas as credenciais (base URL, usuário, senha e token)
  static Future<void> deleteCredentials() async {
    await _storage.delete(key: _baseUrlKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _tokenKey);
  }

  static Future<void> clearUsername() async {
    await _storage.delete(key: _usernameKey);
  }

  static Future<void> clearPassword() async {
    await _storage.delete(key: _passwordKey);
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';
import 'config_service.dart';

class AuthService {
  String? _token;
  DateTime? _tokenExpiration;

  /// 🔹 Executa login explícito recebendo usuário e senha,
  /// salva as credenciais e força a autenticação imediatamente.
  Future<bool> authenticate(String username, String password) async {
    try {
      // Salva credenciais para uso futuro
      await SecureStorageService.saveUsername(username);
      await SecureStorageService.savePassword(password);

      // Força uma nova autenticação (gera e armazena o token)
      await _authenticateUser();
      return true;
    } catch (e) {
      debugPrint('❌ Erro na autenticação: $e');
      return false;
    }
  }

  /// 🔹 Obtém um token válido
  Future<String> getToken() async {
    if (_token != null &&
        _tokenExpiration != null &&
        DateTime.now().isBefore(_tokenExpiration!)) {
      return _token!;
    }
    return await _authenticateUser();
  }

  /// 🔹 Autentica o usuário e obtém um novo token
  Future<String> _authenticateUser() async {
    final String? baseUrl = await ConfigService.getBaseUrl();
    final String? username = await SecureStorageService.getUsername();
    final String? password = await SecureStorageService.getPassword();

    if (baseUrl == null || username == null || password == null) {
      throw Exception("⚠️ Credenciais não configuradas.");
    }

    final String authUrl = '$baseUrl/cisspoder-auth/oauth/token';

    print("🔄 Tentando autenticação...");
    print("🌍 URL: $authUrl");
    print("👤 Usuário: $username");

    final response = await http.post(
      Uri.parse(authUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': 'cisspoder-oauth',
        'client_secret': 'poder7547',
        'grant_type': 'password',
        'username': username,
        'password': password,
      },
    );

    print("🔄 Resposta da API (${response.statusCode}): ${response.body}");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _token = data['access_token'];
      _tokenExpiration = DateTime.now().add(const Duration(hours: 24));
      await SecureStorageService.saveToken(_token!);

      print("✅ Token autenticado com sucesso!");
      return _token!;
    } else {
      throw Exception('❌ Falha na autenticação. Código: ${response.statusCode}');
    }
  }

  /// 🔹 Atualiza a conexão e força uma nova autenticação
  Future<bool> updateConnection() async {
    try {
      print("🔄 Atualizando conexão...");

      // 🚨 Remove o token antigo antes de autenticar novamente
      await clearToken();

      String? baseUrl = await ConfigService.getBaseUrl();
      String? username = await SecureStorageService.getUsername();
      String? password = await SecureStorageService.getPassword();

      if (baseUrl != null && username != null && password != null) {
        print("🌐 Nova conexão configurada: $baseUrl");

        // ✅ Apenas força uma nova autenticação com as credenciais atualizadas
        await _authenticateUser(); // Aqui é onde o token é renovado, mas sem buscar dados da API.

        // 🔹 Aguarda um tempo antes de retornar sucesso
        await Future.delayed(const Duration(milliseconds: 500));

        print("✅ Nova conexão autenticada com sucesso!");
        return true;
      } else {
        print("⚠️ Configuração incompleta. Falha na atualização.");
        return false;
      }
    } catch (e) {
      print("❌ Erro ao atualizar conexão: $e");
      return false;
    }
  }



  /// 🔹 Remove o token armazenado
  Future<void> clearToken() async {
    _token = null;
    _tokenExpiration = null;
    await SecureStorageService.clearToken();
    print("🗑️ Token removido.");
  }
  /// 🔒 Realiza logout do usuário, limpando apenas dados de autenticação.
  Future<void> logout() async {
    _token = null;
    _tokenExpiration = null;
    await SecureStorageService.clearToken();
    await SecureStorageService.clearUsername();
    await SecureStorageService.clearPassword();
    print("🔓 Logout realizado com sucesso (credenciais apagadas, conexão mantida).");
  }
}

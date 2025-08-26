import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../api/api_config.dart';
import 'package:flutter/material.dart';
import '../core/global_context.dart';

class ApiClient {
  final AuthService authService;

  ApiClient(this.authService);

  Future<dynamic> postService(String service, {Map<String, dynamic>? body}) async {
    try {
      // 🔹 Sempre pega o token atualizado ANTES da requisição
      final token = await authService.getToken();

      // Obtém a URL base configurada dinamicamente
      final String serviceUrl = await ApiConfig.serviceUrl(service);  // Usa a URL da API configurada

      // Se a URL for HTTP, faça a validação de segurança
      if (serviceUrl.startsWith("http://")) {
        print("⚠️ Conectando sem SSL (HTTP), verifique se o servidor está configurado corretamente.");
      }

      print('📢 Chamando API: $serviceUrl');
      print('📦 Enviando dados: ${json.encode(body)}');

      // Se os dados incluírem campos como senha, vamos codificar a senha
      if (body != null && body['password'] != null) {
        // Codifica a senha para garantir que caracteres especiais não quebrem a URL
        body['password'] = Uri.encodeComponent(body['password']);
      }

      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(serviceUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(body ?? {'page': 1}),
        );

        print('🔹 Resposta da API (${response.statusCode}): ${response.body}');

        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else if (response.statusCode == 401) {
          print("⚠️ Token inválido! Atualizando...");
          await authService.clearToken(); // 🔹 Remove o token antigo
          await authService.getToken(); // 🔹 Obtém um novo token
          return await postService(service, body: body); // 🔄 **Tenta a requisição novamente**
        } else {
          // Detecta endpoint inexistente (404) ou serviço não cadastrado (500 com NullPointerException)
          final bool endpointNaoExiste =
              response.statusCode == 404 ||
                  (response.statusCode == 500 &&
                      response.body.contains('NullPointerException') &&
                      response.body.contains('No message available'));

          if (endpointNaoExiste) {
            _showSnack('Serviço não encontrado. Peça ao responsável para cadastrá-lo.');
          }

          throw Exception('Erro na API: ${response.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (e is SocketException) {
        throw Exception('Erro de conexão com o servidor: ${e.message}');
      }
      throw Exception('Erro inesperado: ${e.toString()}');
    }
  }
  void _showSnack(String msg) {
    final ctx = GlobalContext.ctx;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // 1️⃣ Fecha o diálogo
                    Navigator.of(context).pop();
                    // 2️⃣ Retorna para a página anterior, se possível
                    final rootCtx = GlobalContext.ctx;
                    if (rootCtx != null && Navigator.of(rootCtx).canPop()) {
                      Navigator.of(rootCtx).pop();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF2E7D32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Fechar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

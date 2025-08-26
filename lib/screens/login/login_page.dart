import 'dart:async';

import 'package:flutter/material.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/access_validator.dart';
import 'package:analyzepro/screens/login/config_dialog.dart';

import '../../services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginPage extends StatefulWidget {
  final AuthService authService;
  final ApiClient apiClient;
  const LoginPage({
    super.key,
    required this.authService,
    required this.apiClient,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  bool _rememberMe = false;
  String? _errorLog;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _loadSavedCredentials() async {
    const storage = FlutterSecureStorage();
    final savedUser = await storage.read(key: 'saved_username');
    final savedPass = await storage.read(key: 'saved_password');
    if (!mounted) return;
    if (savedUser != null && savedPass != null) {
      setState(() {
        _usernameController.text = savedUser;
        _passwordController.text = savedPass;
        _rememberMe = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _errorLog = null;
    });

    setState(() => _loading = true);

    try {
      final success = await widget.authService
          .authenticate(_usernameController.text.trim(), _passwordController.text)
          .timeout(const Duration(seconds: 10), onTimeout: () => throw TimeoutException('Timeout na autenticação'));

      if (!mounted) return;

      if (!success) {
        setState(() {
          _errorLog = 'Ops! Erro ao autenticar. Verifique url, usuário e senha.';
          _loading = false;
        });
        return;
      }

      // Faz a validação completa (licença, pagamento, etc.)
      final validator = AccessValidator(widget.apiClient);
      final authorized = await validator.validateAccess();

      setState(() => _loading = false);

      if (!authorized) {
        setState(() => _loading = false);
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text("Acesso Negado"),
            content: const Text(
              "Pagamento em atraso. Verifique com o comercial.\n\n"
              "Clique em 'Já fiz o Pagamento' para revalidar.",
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop(); // fecha o dialog
                  setState(() => _loading = true);
                  final reauthorized = await validator.validateAccess(force: true);
                  setState(() => _loading = false);
                  if (reauthorized) {
                    // prossegue com login bem-sucedido
                    if (_rememberMe) {
                      const storage = FlutterSecureStorage();
                      await storage.write(key: 'saved_username', value: _usernameController.text.trim());
                      await storage.write(key: 'saved_password', value: _passwordController.text);
                    }
                    Navigator.pushReplacementNamed(context, '/home');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Ainda não está autorizado.")),
                    );
                  }
                },
                child: const Text("Já fiz o Pagamento"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openConfigDialog();
                },
                child: const Text("Ajustar Conexão"),
              ),
            ],
          ),
        );
        return;
      }

      // Salva ou remove credenciais conforme checkbox
      const storage = FlutterSecureStorage();
      if (_rememberMe) {
        await storage.write(key: 'saved_username', value: _usernameController.text.trim());
        await storage.write(key: 'saved_password', value: _passwordController.text);
      } else {
        await storage.delete(key: 'saved_username');
        await storage.delete(key: 'saved_password');
      }

      // Tudo certo → navega para Home
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      final String message;
      if (e.toString().contains('SocketException')) {
        message = 'Erro de conexão: não foi possível se comunicar com o servidor. Verifique a internet ou as configurações.';
      } else if (e.toString().contains('TimeoutException')) {
        message = 'Tempo de conexão esgotado. O servidor demorou muito para responder.';
      } else {
        message = 'Erro inesperado:\n$e';
      }
      setState(() {
        _loading = false;
        _errorLog = message;
      });
    }
  }

  void _openConfigDialog() {
    showDialog(
      context: context,
      builder: (_) => ConfigDialog(
        // Apenas fecha o próprio diálogo; não altera a rota
        onConfigUpdated: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Conteúdo principal
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          SizedBox(
                            width: 250,
                            height: 250,
                            child: Image.asset('assets/login/logo.png', fit: BoxFit.contain),
                          ),
                          const Text(
                            "Analyze",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Bem-vindo de volta!",
                            style: TextStyle(fontSize: 16, color: Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            )
                          ],
                        ),
                        child: TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            hintText: 'Username',
                            prefixIcon: Icon(Icons.person),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Informe o usuário' : null,
                        ),
                      ),

                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            )
                          ],
                        ),
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                          onFieldSubmitted: (_) => _login(),
                          validator: (value) =>
                              (value == null || value.isEmpty) ? 'Informe a senha' : null,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Checkbox "Lembrar"
                      CheckboxListTile(
                        value: _rememberMe,
                        onChanged: (val) => setState(() => _rememberMe = val ?? false),
                        title: const Text(
                          'Lembrar minhas credenciais',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 14,
                          ),
                        ),
                        activeColor: Color(0xFF2E7D32),
                        checkColor: Colors.white,
                        side: BorderSide(color: Color(0xFF2E7D32), width: 2),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity(horizontal: -4, vertical: -2),
                      ),
                      const SizedBox(height: 8),

                      if (_errorLog != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            border: Border.all(color: Colors.red),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _errorLog!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],

                      // Botão Entrar
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32), // verde escuro vibrante
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  "Entrar",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _openConfigDialog,
                        //icon: Icon(Icons.settings, color: Color(0xFF2E7D32)),
                        label: Text(
                          "Configurar conexão",
                          style: TextStyle(color: Color(0xFF2E7D32)),
                        ),
                      ),

                      const SizedBox(height: 30),
                      Text(
                        "Versão 1.0.24",
                        style: TextStyle(color: Color(0xFF2E7D32)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

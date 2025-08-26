import 'dart:async';
import 'package:flutter/material.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:analyzepro/services/config_validation.dart';
import '../screens/login/config_dialog.dart';
import 'access_validator.dart';

class AccessControlWrapper extends StatefulWidget {
  final Widget child;
  final ApiClient apiClient;
  final AuthService authService;

  const AccessControlWrapper({
    Key? key,
    required this.child,
    required this.apiClient,
    required this.authService,
  }) : super(key: key);

  @override
  _AccessControlWrapperState createState() => _AccessControlWrapperState();
}

class _AccessControlWrapperState extends State<AccessControlWrapper> {
  Timer? _validationTimer;
  Timer? _loadingTimer;
  bool forceRevalidationOnStartup = false;

  @override
  void initState() {
    super.initState();
    print('AccessControlWrapper: iniciado');
    _startValidationTimer();
  }

  void _startValidationTimer() async {
    // Aguarda um pequeno delay para garantir que o cache esteja atualizado
    await Future.delayed(const Duration(seconds: 3));
    final prefs = await SharedPreferences.getInstance();
    bool cachedAccess = prefs.getBool("accessAuthorized") ?? false;
    int? lastValidationTimestamp = prefs.getInt("lastValidationTimestamp");

    // 🚫 Verifica se o cache venceu com base na data de liberação
    int? grantedTimestamp = prefs.getInt('accessGrantedAt');
    DateTime? grantedDate = grantedTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(grantedTimestamp)
        : null;

    DateTime now = DateTime.now();
    // NOVO BLOCO CONFORME INSTRUÇÃO:
    if (grantedDate != null) {
      print('AccessControlWrapper: Acesso concedido em: $grantedDate');
      DateTime expiresAt = grantedDate.add(maxAccessDuration);
      print('AccessControlWrapper: Válido até: $expiresAt');
      print('AccessControlWrapper: Agora: $now');

      if (now.isAfter(expiresAt)) {
        print('AccessControlWrapper: Limite de 37 dias excedido. Acesso bloqueado.');
        _validationTimer = Timer(const Duration(seconds: 1), _showAccessDeniedModal);
        return;
      }
    } else {
      print('AccessControlWrapper: Nenhuma data de liberação registrada. Será necessário revalidar com a API.');
    }

    print('AccessControlWrapper: ✅ Cache autorizado: $cachedAccess');
    print('AccessControlWrapper: ⏱️ Último timestamp de validação: ${DateTime.fromMillisecondsSinceEpoch(lastValidationTimestamp ?? 0)}');

    // Se o acesso estiver autorizado e o cache for recente, não dispara o modal.
    if (cachedAccess && lastValidationTimestamp != null) {
      DateTime lastValidation = DateTime.fromMillisecondsSinceEpoch(
          lastValidationTimestamp);
      Duration diff = DateTime.now().difference(lastValidation);
      // print removido para evitar duplicação

      final int minutes = diff.inMinutes.remainder(60);
      final int seconds = diff.inSeconds.remainder(60);
      final int hours = diff.inHours;

      String readableDiff = '';
      if (hours > 0) readableDiff += '${hours}h ';
      if (minutes > 0) readableDiff += '${minutes}min ';
      readableDiff += '${seconds}s';

      print('AccessControlWrapper: 🕒 Última validação foi há $readableDiff ($lastValidation)');

      if (diff < validationCacheDuration) {
        print('AccessControlWrapper: ✅ Não foi enviado requisição para a API, usando cache.');
        return;
      }
    }

    // Se não houver timestamp ou o cache expirou, força a revalidação:
    final validator = AccessValidator(widget.apiClient);
    bool newAuthorized = await validator.validateAccess(force: true);
    print('AccessControlWrapper: 🚀 Enviado requisição para a API.');
    print('AccessControlWrapper: 🔁 Nova validação retornou: $newAuthorized');
    if (newAuthorized) {
      await updateValidationResult(true);
      print(
          'AccessControlWrapper: Cache atualizado. Acesso permanece autorizado.');
    } else {
      print('AccessControlWrapper: Acesso bloqueado após nova validação.');
      _validationTimer =
          Timer(const Duration(seconds: 1), _showAccessDeniedModal);
    }
  }

  Future<void> _showAccessDeniedModal() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text("Acesso Negado"),
            content: const Text(
              "Pagamento em atraso. Verifique com o comercial.\n\nClique em 'Já fiz o Pagamento' para revalidar.",
            ),
            actions: [
              TextButton(
                onPressed: () => _handlePaymentValidation(context),
                child: const Text("Já fiz o Pagamento"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context, rootNavigator: true).pop(); // Fecha o modal atual
                  await showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ConfigDialog(
                      onConfigUpdated: () {
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                          builder: (context) => AccessControlWrapper(
                            child: widget.child,
                            apiClient: widget.apiClient,
                            authService: widget.authService,
                          ),
                        ));
                      },
                    ),
                  );
                },
                child: const Text("Ajustar conexão"),
              ),
            ],
          ),
        );
      },
    );
  }


  Future<void> _handlePaymentValidation(BuildContext context) async {
    // Exibe um modal de loading enquanto a validação ocorre.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text("Aguardando Liberação"),
              ],
            ),
          ),
    );

    _loadingTimer = Timer(const Duration(minutes: 1), () {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Tempo esgotado. Por favor, tente novamente.")),
      );
    });

    try {
      final validator = AccessValidator(widget.apiClient);
      bool authorized = await validator.validateAccess(force: true);
      print(
          'AccessControlWrapper: Resultado da revalidação (force=true): $authorized');
      _loadingTimer?.cancel();
      Navigator.of(context, rootNavigator: true)
          .pop(); // Fecha o modal de loading

      if (authorized) {
        await updateValidationResult(true);
        Navigator.of(context, rootNavigator: true)
            .pop(); // Fecha o modal de acesso negado
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (context) => widget.child,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Ainda não encontramos seu CNPJ autorizado.")),
        );
      }
    } catch (e) {
      _loadingTimer?.cancel();
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Erro durante a verificação. Tente novamente.")),
      );
    }
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🚀 Entrou na AccessControlWrapper');
    return PopScope(
      canPop: false,
      child: widget.child,
    );
  }
}
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_config.dart';
import '../api/api_client.dart';
import 'config_validation.dart';
import 'package:intl/intl.dart';

class AccessValidator {
  final ApiClient apiClient;

  AccessValidator(this.apiClient);

  /// Valida se algum dos CNPJs retornados pela API "cad_lojas"
  /// está na lista autorizada obtida do Google Sheets.
  /// Se houver um resultado em cache válido (dentro de validationCacheDuration),
  /// esse resultado é retornado; caso contrário, a validação é refeita e o cache é atualizado.
  Future<bool> validateAccess({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (force) {
      await prefs.remove('accessAuthorized');
      await prefs.remove('lastValidationTimestamp');
    }
    final lastValidationTimestamp = prefs.getInt("lastValidationTimestamp");

    // Se houver cache e estiver dentro do período, retorne o valor armazenado.
    if (!force && lastValidationTimestamp != null) {
      DateTime lastValidation = DateTime.fromMillisecondsSinceEpoch(lastValidationTimestamp);
      if (DateTime.now().difference(lastValidation) < validationCacheDuration) {
        bool cachedResult = prefs.getBool("accessAuthorized") ?? false;
        print('AccessValidator (Cache): Usando resultado de acesso em cache: $cachedResult');
        return cachedResult;
      }
    }

    // Caso não haja cache válido, refaz a validação:
    // Dados da planilha do Google Sheets e API Key
    const String sheetId = '1HcxwXalPEZbsLVcf0U1qC4Uq530e7fd8OqX13VH6d-4';
    const String apiKey = 'AIzaSyDOi-m9xO2ngcssDvKKIvMAh2Lf7G-ENrU'; // Sua API Key
    final String sheetUrl =
        'https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/CNPJs?key=$apiKey';

    // Corpo da requisição para a API "cad_lojas" – busca todos os registros
    final body = {
      'page': 1,
      'limit': 100,
      'clausulas': []
    };

    print('AccessValidator: Enviando requisição para API cad_lojas com body: ${json.encode(body)}');
    try {
      final urlApi = await ApiConfig.serviceUrl('cad_lojas');
      print('AccessValidator: URL da API cad_lojas: $urlApi');
      final token = await apiClient.authService.getToken();
      print('AccessValidator: Token obtido: $token');

      final response = await http.post(
        Uri.parse(urlApi),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(body),
      );

      print('AccessValidator: Resposta da API cad_lojas: ${response.statusCode}');
      print('AccessValidator: Corpo da resposta: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null && (data['data'] as List).isNotEmpty) {
          List<String> cnpjsApi = (data['data'] as List)
              .map<String>((loja) => loja['cnpj'].toString().trim())
              .toList();
          print('AccessValidator: CNPJs retornados pela API: $cnpjsApi');

          // Consulta os CNPJs autorizados na planilha
          final sheetResponse = await http.get(Uri.parse(sheetUrl));
          print('AccessValidator: Resposta da planilha: ${sheetResponse.statusCode}');
          print('AccessValidator: Corpo da resposta da planilha: ${sheetResponse.body}');

          if (sheetResponse.statusCode == 200) {
            final sheetData = json.decode(sheetResponse.body);

            final linhas = sheetData['values'] as List;
            bool authorized = false;

            for (int i = 1; i < linhas.length; i++) {
              final row = linhas[i];
              final status = row[0]?.toString().trim().toLowerCase() ?? '';
              final cnpjPlanilha = row[2]?.toString().trim() ?? '';
              final ultimoPagamentoStr = row[3]?.toString().trim();

              if (cnpjsApi.contains(cnpjPlanilha)) {
                if (!status.contains('mensalidade atrasada') && ultimoPagamentoStr != null && ultimoPagamentoStr.isNotEmpty) {
                  try {
                    final pagamento = DateFormat('dd/MM/yyyy').parse(ultimoPagamentoStr);
                    final grantedDate = pagamento;
                    final validade = grantedDate.add(const Duration(days: 37));
                    final now = DateTime.now();

                    if (now.isBefore(validade)) {
                      await prefs.setInt('accessGrantedAt', grantedDate.millisecondsSinceEpoch);
                      await updateValidationResult(true);
                      print('AccessValidator: Acesso liberado com base no último pagamento em $ultimoPagamentoStr. Válido até $validade');
                      return true;
                    } else {
                      print('AccessValidator: Pagamento expirado. Último pagamento em $ultimoPagamentoStr');
                    }
                  } catch (e) {
                    print('AccessValidator: Erro ao converter data de pagamento: $ultimoPagamentoStr');
                  }
                }
              }
            }

            print('AccessValidator: Nenhum CNPJ autorizado com pagamento válido encontrado.');
            await updateValidationResult(false);
            return false;
          } else {
            print('AccessValidator: Erro ao acessar a planilha: ${sheetResponse.statusCode}');
            return false;
          }
        } else {
          print('AccessValidator: Nenhum CNPJ retornado pela API.');
          return false;
        }
      } else {
        print('AccessValidator: Erro na chamada da API cad_lojas: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('AccessValidator: Erro durante a validação de acesso: $e');
      return false;
    }
  }
}

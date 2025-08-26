import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/financeiro/contas_pagar.dart';

class ContasPagarRepository {
  final ApiClient apiClient;

  ContasPagarRepository(this.apiClient);

  Future<List<ContasPagar>> getResumoContasPagarMultiplasEmpresas({
    required List<int> empresasIds,
    required DateTime dataInicial,
    required DateTime dataFinal,
    int limit = 1000,
  }) async {
    final body = {
      "limit": limit,
      "page": 1,
      "clausulas": [
        {
          "campo": "idempresa",
          "valor": empresasIds,
          "operadorlogico": "AND",
          "operador": "IN"
        },
        {
          "campo": "ra_dtini",
          "valor": dataInicial.toIso8601String().split("T")[0],
          "operadorlogico": "AND",
          "operador": "IGUAL"
        },
        {
          "campo": "ra_dtfim",
          "valor": dataFinal.toIso8601String().split("T")[0],
          "operadorlogico": "AND",
          "operador": "IGUAL"
        }
      ]
    };

    final resp = await apiClient.postService(
      'insights/contas_pagar_vencimento',
      body: body,
    );

    if (resp == null || resp['data'] == null || (resp['data'] as List).isEmpty) {
      throw Exception('Resposta vazia ou inválida ao carregar resumo contas a pagar.');
    }

    final dataList = resp['data'] as List;
    return dataList.map((item) => ContasPagar.fromJson(item as Map<String, dynamic>)).toList();
  }
}

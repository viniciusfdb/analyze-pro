import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/financeiro/contas_receber_vencimento.dart';

class ContasReceberRepository {
  final ApiClient api;

  ContasReceberRepository(this.api);

  /// Busca resumo consolidado de Contas a Receber para múltiplas empresas e intervalo de datas.
  ///
  /// [empresasIds] deve conter os IDs das empresas desejadas.
  /// Retorna uma lista de ContasReceber, uma para cada empresa retornada pela API.
  Future<List<ContasReceber>> getResumoContasReceberMultiplasEmpresas({
    required List<int> empresasIds,
    required DateTime dataInicial,
    required DateTime dataFinal,
    int limit = 1000,
  }) async {
    print('[🔍 CHAMADA API] idempresas=$empresasIds, dtini=$dataInicial, dtfim=$dataFinal');
    final resp = await api.postService(
      'insights/contas_receber_vencimento',
      body: {
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
      },
    );

    final data = resp['data'] as List;
    if (data.isEmpty) {
      throw Exception('Nenhum dado retornado para o resumo de contas a receber.');
    }
    // retorna todos os resultados por empresa
    return data.map((json) => ContasReceber.fromJson(json)).toList();
  }

  Future<List<ContasReceber>> getContasReceberPaginado({
    required int limit,
    required int page,
  }) async {
    final resp = await api.postService(
      'insights/contas_receber_vencimento',
      body: {
        "limit": limit,
        "page": page,
      },
    );

    final data = resp['data'] as List;
    return data.map((item) => ContasReceber.fromJson(item)).toList();
  }
}
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/financeiro/inadimplencia.dart';

class InadimplenciaRepository {
  final ApiClient api;

  InadimplenciaRepository(this.api);

  /// Busca resumo de inadimplência para múltiplas empresas e intervalo de datas.
  ///
  /// [empresasIds] deve conter os IDs das empresas desejadas.
  /// Retorna uma lista de Inadimplencia, uma para cada empresa retornada pela API.
  Future<List<Inadimplencia>> getResumoInadimplenciaMultiplasEmpresas({
    required List<int> empresasIds,
    required DateTime dataInicial,
    required DateTime dataFinal,
    int limit = 1000,
  }) async {
    print('[🔍 CHAMADA API] inadimplencia: idempresas=$empresasIds, dtini=$dataInicial, dtfim=$dataFinal');
    final resp = await api.postService(
      'insights/inadimplencia',
      body: {
        "limit": limit,
        "page": 1,
        "clausulas": [
          {
            "campo": "ra_idempresa",
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
      throw Exception('Nenhum dado retornado para o resumo de inadimplência.');
    }

    return data.map((json) => Inadimplencia.fromJson(json)).toList();
  }
}
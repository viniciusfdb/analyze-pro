import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/vendas/faturamento_com_lucro_model.dart';

class FaturamentoComLucroRepository {
  final ApiClient api;

  FaturamentoComLucroRepository(this.api);

  Future<List<FaturamentoComLucro>> getFaturamentoComLucroPaginado({
    required int limit,
    required int page,
    required int idEmpresa,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final resp = await api.postService(
      'insights/faturamento_com_lucro',
      body: {
        "limit": limit,
        "page": page,
        "clausulas": [
          {
            "campo": "idempresa",
            "valor": idEmpresa,
            "operador": "IGUAL"
          },
          {
            "campo": "dtmovimento",
            "valor": [
              dataInicial.toIso8601String().split("T")[0],
              dataFinal.toIso8601String().split("T")[0]
            ],
            "operadorLogico": "AND",
            "operador": "BETWEEN"
          }
        ]
      },
    );

    final data = resp['data'] as List;
    return data.map((item) => FaturamentoComLucro.fromJson(item)).toList();
  }

  Future<List<FaturamentoComLucro>> getResumoFaturamentoComLucro({
    required int idEmpresa,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final result = await getFaturamentoComLucroPaginado(
      limit: 1000,
      page: 1,
      idEmpresa: idEmpresa,
      dataInicial: dataInicial,
      dataFinal: dataFinal,
    );
    return result;
  }
}
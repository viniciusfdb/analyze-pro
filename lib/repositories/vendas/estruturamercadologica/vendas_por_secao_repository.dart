

import 'package:analyzepro/api/api_client.dart';

import '../../../models/vendas/estruturamercadologica/vendas_por_secao_model.dart';

class VendasPorSecaoRepository {
  final ApiClient api;

  VendasPorSecaoRepository(this.api);

  Future<List<VendaPorSecaoModel>> getVendasPorSecao({
    required int idEmpresa,
    int? idDivisao,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final resp = await api.postService(
      'insights/faturamento_com_lucro_secao',
      body: {
        "limit": 1000,
        "page": 1,
        "clausulas": [
          {
            "campo": "ra_idempresa",
            "valor": idEmpresa,
            "operador": "IGUAL"
          },
          {
            "campo": "ra_iddivisao",
            "valor": idDivisao,
            "operador": "IGUAL"
          },
          {
            "campo": "ra_dtini",
            "valor": dataInicial.toIso8601String().split("T")[0],
            "operador": "MAIOR_IGUAL"
          },
          {
            "campo": "ra_dtfim",
            "valor": dataFinal.toIso8601String().split("T")[0],
            "operador": "MENOR_IGUAL"
          }
        ]
      },
    );

    final data = resp['data'] as List;
    return data.map((item) => VendaPorSecaoModel.fromJson(item)).toList();
  }
}
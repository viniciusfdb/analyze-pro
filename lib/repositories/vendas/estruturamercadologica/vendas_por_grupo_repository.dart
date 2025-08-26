

import 'package:analyzepro/api/api_client.dart';
import '../../../models/vendas/estruturamercadologica/vendas_por_grupo_model.dart';

class VendasPorGrupoRepository {
  final ApiClient api;

  VendasPorGrupoRepository(this.api);

  Future<List<VendaPorGrupoModel>> getVendasPorGrupo({
    required int idEmpresa,
    int? idSecao,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final clausulas = [
      {
        "campo": "ra_idempresa",
        "valor": idEmpresa,
        "operador": "IGUAL"
      },
      if (idSecao != null)
        {
          "campo": "ra_idsecao",
          "valor": idSecao,
          "operador": "IGUAL"
        }
      else
        {
          "campo": "ra_idsecao",
          "valor": null,
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
    ];
    final resp = await api.postService(
      'insights/faturamento_com_lucro_grupo',
      body: {
        "limit": 1000,
        "page": 1,
        "clausulas": clausulas
      },
    );

    final data = resp['data'] as List;
    return data.map((item) => VendaPorGrupoModel.fromJson(item)).toList();
  }
}
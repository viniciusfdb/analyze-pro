import 'package:analyzepro/api/api_client.dart';
import '../../../models/vendas/estruturamercadologica/vendas_por_subgrupo_model.dart';

class VendasPorSubgrupoRepository {
  final ApiClient api;

  VendasPorSubgrupoRepository(this.api);

  Future<List<VendaPorSubgrupoModel>> getVendasPorSubgrupo({
    required int idEmpresa,
    int? idGrupo,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final clausulas = [
      {
        "campo": "ra_idempresa",
        "valor": idEmpresa,
        "operador": "IGUAL"
      },
      if (idGrupo != null)
        {
          "campo": "ra_idgrupo",
          "valor": idGrupo,
          "operador": "IGUAL"
        }
      else
        {
          "campo": "ra_idgrupo",
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
      'insights/faturamento_com_lucro_subgrupo',
      body: {
        "limit": 1000,
        "page": 1,
        "clausulas": clausulas
      },
    );

    final data = resp['data'] as List;
    return data.map((item) => VendaPorSubgrupoModel.fromJson(item)).toList();
  }
}
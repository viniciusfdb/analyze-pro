

import 'package:analyzepro/api/api_client.dart';
import '../../../models/vendas/estruturamercadologica/vendas_por_vendedor_subgrupo_model.dart';

class VendasPorVendedorSubgrupoRepository {
  final ApiClient api;

  VendasPorVendedorSubgrupoRepository(this.api);

  Future<List<VendaPorVendedorSubgrupoModel>> getVendasPorVendedorSubgrupo({
    required int idEmpresa,
    required int idVendedor,
    required int idGrupo,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final response = await api.postService(
      'insights/vendas_por_vendedor_subgrupo',
      body: {
        "page": 1,
        "limit": 1000,
        "clausulas": [
          {
            "campo": "ra_idempresa",
            "valor": idEmpresa,
            "operador": "IGUAL"
          },
          {
            "campo": "ra_idvendedor",
            "valor": idVendedor,
            "operador": "IGUAL"
          },
          {
            "campo": "ra_idgrupo",
            "valor": idGrupo,
            "operador": "IGUAL"
          },
          {
            "campo": "ra_dtini",
            "valor": dataInicial.toIso8601String().split('T').first,
            "operador": "MAIOR_IGUAL"
          },
          {
            "campo": "ra_dtfim",
            "valor": dataFinal.toIso8601String().split('T').first,
            "operador": "MENOR_IGUAL"
          },
        ]
      },
    );

    final lista = response['data'] as List<dynamic>;
    return lista
        .map((json) => VendaPorVendedorSubgrupoModel.fromJson(json))
        .toList();
  }
}
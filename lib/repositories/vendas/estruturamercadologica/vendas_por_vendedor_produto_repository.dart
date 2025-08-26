import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/vendas/estruturamercadologica/vendas_por_vendedor_produto_model.dart';

class VendasPorVendedorProdutoRepository {
  final ApiClient api;

  VendasPorVendedorProdutoRepository(this.api);

  Future<List<VendaPorVendedorProdutoModel>> getVendasPorVendedorProduto({
    required int idEmpresa,
    required int idVendedor,
    required int idSubgrupo,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final resp = await api.postService(
      'insights/vendas_por_vendedor_produto',
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
            "campo": "ra_idsubgrupo",
            "valor": idSubgrupo,
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

    final lista = resp['data'] as List<dynamic>;
    return lista
        .map((json) => VendaPorVendedorProdutoModel.fromJson(json))
        .toList();
  }
}
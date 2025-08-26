import 'package:analyzepro/api/api_client.dart';

import '../../../../models/vendas/estruturamercadologica/vendas_por_produto_model.dart';

class VendasPorProdutoRepository {
  final ApiClient api;

  VendasPorProdutoRepository(this.api);

  Future<List<VendaPorProdutoModel>> getVendasPorProduto({
    int? idEmpresa,
    List<int>? idsEmpresa,
    int? idSubgrupo,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    // Monta clausulas fora do loop, garantindo idSubgrupo como null quando necessário
    final clausulas = [
      if (idsEmpresa != null)
        {
          "campo": "ra_idempresa",
          "valor": idsEmpresa,
          "operador": "IN"
        }
      else if (idEmpresa != null)
        {
          "campo": "ra_idempresa",
          "valor": idEmpresa,
          "operador": "IGUAL"
        },
      {
        "campo": "ra_idsubgrupo",
        "valor": idSubgrupo,
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

    int page = 1;
    const int limit = 1000;
    bool hasNext = true;
    List<VendaPorProdutoModel> resultados = [];

    while (hasNext) {
      final response = await api.postService(
        'insights/faturamento_com_lucro_produto',
        body: {
          'limit': limit,
          'page': page,
          'clausulas': clausulas,
        },
      );

      final dados = (response['data'] as List)
          .map((e) => VendaPorProdutoModel.fromJson(e))
          .toList();

      resultados.addAll(dados);

      hasNext = dados.length == limit;
      page++;
    }

    return resultados;
  }
}
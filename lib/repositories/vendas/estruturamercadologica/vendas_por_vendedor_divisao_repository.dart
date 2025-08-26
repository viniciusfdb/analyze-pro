import 'package:analyzepro/api/api_client.dart';
import '../../../models/vendas/estruturamercadologica/vendas_por_vendedor_divisao_model.dart';

class VendasPorVendedorDivisaoRepository {
  final ApiClient api;

  VendasPorVendedorDivisaoRepository(this.api);

  Future<List<VendaPorVendedorDivisaoModel>> getVendasPorVendedorDivisao({
    required int idEmpresa,
    required int idVendedor,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final resp = await api.postService(
      'insights/vendas_por_vendedor_divisao',
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
            "campo": "ra_idvendedor",
            "valor": idVendedor,
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
    return data.map((item) => VendaPorVendedorDivisaoModel.fromJson(item)).toList();
  }
}
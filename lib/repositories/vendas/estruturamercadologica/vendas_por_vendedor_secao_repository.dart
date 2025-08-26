import 'package:analyzepro/api/api_client.dart';
import '../../../models/vendas/estruturamercadologica/vendas_por_vendedor_secao_model.dart';

class VendasPorVendedorSecaoRepository {
  final ApiClient api;

  VendasPorVendedorSecaoRepository(this.api);

  Future<List<VendaPorVendedorSecaoModel>> getVendasPorVendedorSecao({
    required int idEmpresa,
    required int idVendedor,
    int? idDivisao,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final clausulas = [
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
        "campo": "ra_iddivisao",
        "valor": idDivisao,
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
    ];

    final response = await api.postService(
      'insights/vendas_por_vendedor_secao',
      body: {
        "page": 1,
        "limit": 1000,
        "clausulas": clausulas,
      },
    );

    final lista = response['data'] as List<dynamic>;
    return lista
        .map((json) => VendaPorVendedorSecaoModel.fromJson(json))
        .toList();
  }
}
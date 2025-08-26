import 'package:analyzepro/models/vendas/estruturamercadologica/vendas_por_vendedor_model.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:intl/intl.dart';

class VendasPorVendedorRepository {
  final ApiClient api;
  final DateFormat _formatter = DateFormat('yyyy-MM-dd');

  VendasPorVendedorRepository(this.api);

  Future<List<VendaPorVendedorModel>> getVendasPorVendedor({
    required int idEmpresa,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final body = {
      "page": 1,
      "limit": 1000,
      "clausulas": [
        {
          "campo": "ra_idempresa",
          "valor": idEmpresa,
          "operador": "IGUAL"
        },
        {
          "campo": "ra_dtini",
          "valor": _formatter.format(dataInicial),
          "operador": "MAIOR_IGUAL"
        },
        {
          "campo": "ra_dtfim",
          "valor": _formatter.format(dataFinal),
          "operador": "MENOR_IGUAL"
        }
      ]
    };

    final response = await api.postService(
      'insights/vendas_por_vendedor',
      body: body,
    );
    final list = (response['data'] as List<dynamic>)
        .map((item) => VendaPorVendedorModel.fromJson(item))
        .toList();

    return list;
  }
}
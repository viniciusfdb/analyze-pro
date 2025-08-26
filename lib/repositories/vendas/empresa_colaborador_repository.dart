import 'package:analyzepro/api/api_client.dart';
import '../../models/vendas/empresa_colaborador.dart';

class EmpresaColaboradorRepository {
  final ApiClient api;

  EmpresaColaboradorRepository(this.api);

  Future<List<EmpresaColaborador>> getColaboradoresPorEmpresaAnoMes({
    required int idEmpresa,
    int? ano,
    int? mes,
  }) async {
    final body = {
      "limit": 1000,
      "page": 1,
      "clausulas": [
        {
          "campo": "ra_idempresa",
          "valor": idEmpresa,
          "operador": "IN"
        },
        {
          "campo": "ra_ano",
          "valor": ano,
          "operador": "IGUAL"
        },
        {
          "campo": "ra_mes",
          "valor": mes,
          "operador": "IGUAL"
        }
      ]
    };

    final response = await api.postService(
      'insights/empresa_colaborador',
      body: body,
    );

    final data = response['data'] as List;

    return data.map((item) => EmpresaColaborador.fromJson(item)).toList();
  }
}
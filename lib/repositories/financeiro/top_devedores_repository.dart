import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/financeiro/top_devedor.dart';

class TopDevedoresRepository {
  final ApiClient api;

  TopDevedoresRepository(this.api);

  Future<List<TopDevedor>> fetchTopDevedores({
    required int idEmpresa,
  }) async {
    final body = {
      "limit": 10,
      "clausulas": [
        {
          "campo": "idempresa",
          "valor": idEmpresa,
          "operadorlogico": "AND",
          "operador": "IGUAL"
        },
      ]
    };

    final resp = await api.postService(
      'insights/contas_receber_vencimento_top_devedores',
      body: body,
    );

    final lista = resp['data'] as List;
    return lista.map((json) => TopDevedor.fromJson(json)).toList();
  }
}
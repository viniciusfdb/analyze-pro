import 'package:analyzepro/api/api_client.dart';
import '../../models/estoque/ruptura_percentual.dart';

class RupturaPercentualRepository {
  final ApiClient api;

  RupturaPercentualRepository(this.api);

  /// Busca os percentuais de ruptura via endpoint `insights/ruptura_percentual`.
  Future<List<RupturaPercentual>> fetchRupturaPercentual({
    required int idEmpresa,
    required int idLocalEstoque,
    required bool expBalanca,
    int limit = 1000,
    int page = 1,
  }) async {
    final body = {
      'limit': limit,
      'page': page,
      'clausulas': [
        {
          'campo': 'ra_idempresa',
          'valor': idEmpresa,
          'operadorlogico': 'AND',
          'operador': 'IGUAL',
        },
        {
          'campo': 'ra_idlocalestoque',
          'valor': idLocalEstoque,
          'operadorlogico': 'AND',
          'operador': 'IGUAL',
        },
        {
          'campo': 'ra_expbalanca',
          'valor': expBalanca ? 'T' : 'F',
          'operadorlogico': 'AND',
          'operador': 'IGUAL',
        },
      ],
    };

    final resp = await api.postService(
      'insights/ruptura_percentual',
      body: body,
    );
    final data = resp['data'] as List<dynamic>;

    return data
        .map((item) =>
            RupturaPercentual.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
import 'package:analyzepro/api/api_client.dart';
import 'package:intl/intl.dart';
import '../../models/metas/CadMeta.dart';


class CadMetaRepository {
  final ApiClient apiClient;

  CadMetaRepository(this.apiClient);

  Future<List<CadMeta>> fetchAll({int? idEmpresa, required DateTime dtInicio, required DateTime dtFim}) async {
    final clausulas = [
      if (idEmpresa != null && idEmpresa > 0)
        {
          'campo': 'idempresa',
          'valor': [idEmpresa],
          'operador': 'IN',
          'operadorLogico': 'AND',
        },
      {
        'campo': 'dtinicial',
        'valor': [
          DateFormat('yyyy-MM-dd').format(dtFim),
        ],
        'operador': 'MENOR_IGUAL',
        'operadorLogico': 'AND',
      },
      {
        'campo': 'dtfinal',
        'valor': [
          DateFormat('yyyy-MM-dd').format(dtInicio),
        ],
        'operador': 'MAIOR_IGUAL',
        'operadorLogico': 'AND',
      },
    ];

    List<CadMeta> allMetas = [];
    int page = 1;
    const int limit = 100;
    bool hasNext = true;

    while (hasNext) {
      final response = await apiClient.postService(
        'cad_meta',
        body: {
          'clausulas': clausulas,
          'page': page,
          'limit': limit,
        },
      );

      if (response is Map<String, dynamic> && response.containsKey('data')) {
        final List<dynamic> data = response['data'] as List<dynamic>;
        final List<CadMeta> metasPage = data.map((json) => CadMeta.fromJson(json)).toList();
        allMetas.addAll(metasPage);
        hasNext = data.length == limit;
        page++;
      } else {
        throw Exception('Resposta inesperada da API em cad_meta');
      }
    }

    return allMetas;
  }
}

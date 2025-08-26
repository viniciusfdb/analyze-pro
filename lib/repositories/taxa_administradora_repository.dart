import '../api/api_client.dart';
import '../models/taxa_administradora.dart';

class TaxaAdministradoraRepository {
  final ApiClient apiClient;

  TaxaAdministradoraRepository(this.apiClient);

  Future<List<TaxaAdministradora>> getTaxaAdministradora({
    required int empresa,
    required String dataInicial,
    required String dataFinal,
    int? administradora,
    int? bandeira,
    required int page,
    required int limit,
  }) async {
    final List<Map<String, dynamic>> clausulas = [
      {
        'campo': 'idempresa',
        'valor': empresa,
        'operadorlogico': 'AND',
        'operador': 'IGUAL'
      },
      {
        "campo": "dtmovimento",
        "valor": [dataInicial, dataFinal],
        "operador": "BETWEEN"
      },
    ];

    // Checando os parâmetros administradora e bandeira
    if (administradora != null) {
      clausulas.add({
        'campo': 'idadministradora',
        'valor': administradora,
        'operadorlogico': 'AND',
        'operador': 'IGUAL',
      });
    }

    if (bandeira != null) {
      clausulas.add({
        'campo': 'idbandeira',
        'valor': bandeira,
        'operadorlogico': 'AND',
        'operador': 'IGUAL',
      });
    }

    // Faz a requisição à API para a página específica com o limite
    final response = await apiClient.postService(
      '/insights/taxa_cobrada_adm',
      body: {
        'page': page, // Página da requisição
        'limit': limit, // Limite de registros por página
        'clausulas': clausulas,
      },
    );

    // Verifica se há dados na resposta
    final List<dynamic> data = response['data'] ?? [];
    if (data.isEmpty) {
      // Lidar com o caso quando não há dados
      return [];
    }

    // Ordenando os dados pela diferença (campo "dif") do menor para o maior
    data.sort((a, b) {
      double difA = (a['dif'] as num?)?.toDouble() ?? 0.0;
      double difB = (b['dif'] as num?)?.toDouble() ?? 0.0;
      return difA.compareTo(difB); // Ordenação crescente
    });

    return data.map((json) => TaxaAdministradora.fromJson(json)).toList();
  }
}

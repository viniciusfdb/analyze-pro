import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/vendas/itens_documentos_fiscais_saida.dart';

class ItensDocumentosFiscaisSaidaRepository {
  final ApiClient apiClient;

  ItensDocumentosFiscaisSaidaRepository({required this.apiClient});

  Future<(List<ItensDocumentosFiscaisSaida>, bool)> getItensDocumentosFiscaisSaida({
    required int limit,
    required int page,
    required dynamic idEmpresa, // Pode ser int ou List<int>
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final resp = await apiClient.postService(
      'itens_documentos_fiscais_saida',
      body: {
        "limit": limit,
        "page": page,
        "clausulas": [
          {
            "campo": "idempresa",
            "valor": idEmpresa,
            "operadorlogico": "AND",
            "operador": "IN"
          },
          {
            "campo": "dtmovimento",
            "valor": [
              dataInicial.toIso8601String().split("T")[0],
              dataFinal.toIso8601String().split("T")[0]
            ],
            "operadorLogico": "AND",
            "operador": "BETWEEN"
          }
        ]
      },
    );

    final data = resp['data'] as List;
    final hasNext = (resp['hasNext'] ?? false) as bool;

    final itens = data.map((item) => ItensDocumentosFiscaisSaida.fromJson(item)).toList();

    return (itens, hasNext);
  }
  /// Busca todos os itens documentos fiscais saída, paginando internamente até obter todos os registros.
  Future<List<ItensDocumentosFiscaisSaida>> getTodosItensDocumentosFiscaisSaida({
    required dynamic idEmpresa,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    int page = 1;
    const int limit = 1000;
    bool hasNext = true;
    List<ItensDocumentosFiscaisSaida> todos = [];

    while (hasNext) {
      final (dados, next) = await getItensDocumentosFiscaisSaida(
        limit: limit,
        page: page,
        idEmpresa: idEmpresa,
        dataInicial: dataInicial,
        dataFinal: dataFinal,
      );

      todos.addAll(dados);
      hasNext = next;
      page++;
    }

    return todos;
  }
}
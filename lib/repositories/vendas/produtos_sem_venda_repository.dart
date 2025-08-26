import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/vendas/produto_sem_venda.dart';

class ProdutosSemVendaRepository {
  final ApiClient apiClient;

  ProdutosSemVendaRepository(this.apiClient);

  /// 🔹 Busca os produtos sem venda aplicando os filtros da tela
  Future<List<ProdutoSemVenda>> getProdutosSemVenda({
    required List<int> empresas,
    required int dias,
    String saldoEstoque = "T",
  }) async {
    try {
      int page = 1;
      bool hasNext = true;
      List<ProdutoSemVenda> resultados = [];

      while (hasNext) {
        // Monta os filtros dinamicamente
        final List<Map<String, dynamic>> clausulas = [
          {
            'campo': 'ra_idempresa',
            'valor': empresas,
            'operadorlogico': 'AND',
            'operador': 'IN',
          },
          {
            'campo': 'ra_dias',
            'valor': [dias],
            'operadorlogico': 'AND',
            'operador': 'IGUAL',
          },
          {
            'campo': 'ra_saldoestoque',
            'valor': [saldoEstoque],
            'operadorlogico': 'AND',
            'operador': 'IGUAL',
          },
        ];
        final body = {
          'page': page,
          'limit': 1000,
          'clausulas': clausulas,
        };
        final response = await apiClient.postService(
          'insights/produtos_sem_venda',
          body: body,
        );

        if (response == null || response['data'] == null || !(response['data'] is List)) {
          print("⚠️ resposta inválida na página $page");
          break;
        }

        final List data = response['data'] as List;
        for (var item in data) {
          try {
            resultados.add(ProdutoSemVenda.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            print("❌ falha ao converter item: $e, dado: $item");
          }
        }

        hasNext = response['hasNext'] == true;
        page++;
      }

      return resultados;
    } catch (e) {
      print("❌ Erro ao buscar produtos sem venda: $e");
      return [];
    }
  }

  /// 🔹 Retorna contagem de produtos sem venda agrupados por seção
  Future<List<Map<String, dynamic>>> getResumoPorSecao({
    required List<int> empresas,
    required int dias,
  }) async {
    final List<Map<String, dynamic>> clausulas = [
      {'campo': 'ra_idempresa', 'valor': empresas, 'operadorlogico': 'AND', 'operador': 'IN'},
      if (dias > 0) {'campo': 'ra_dias', 'valor': [dias], 'operadorlogico': 'AND', 'operador': 'IGUAL'},
    ];

    final body = {
      'page': 1,
      'limit': 1000,
      'clausulas': clausulas,
      'agregadores': [
        {'campo': 'descrsecao', 'label': 'quantidade', 'agregador': 'COUNT'},
      ],
    };

    final response = await apiClient.postService(
      'insights/produtos_sem_venda',
      body: body,
    );

    if (response == null || response['data'] == null || response['data'] is! List) {
      print("⚠️ resposta inválida ao resumir por seção");
      return [];
    }

    return (response['data'] as List).map((e) {
      final Map<String, dynamic> item = e as Map<String, dynamic>;
      return {
        'idsecao': item['idsecao'],
        'secao': item['descrsecao'],
        'quantidade': (item['quantidade'] as num).toInt(),
      };
    }).toList();
  }

  /// 🔹 Retorna contagem de produtos sem venda agrupados por divisão
  Future<List<Map<String, dynamic>>> getResumoPorDivisao({
    required List<int> empresas,
    required int dias,
  }) async {
    final List<Map<String, dynamic>> clausulas = [
      {'campo': 'ra_idempresa', 'valor': empresas, 'operadorlogico': 'AND', 'operador': 'IN'},
      if (dias > 0) {'campo': 'ra_dias', 'valor': [dias], 'operadorlogico': 'AND', 'operador': 'IGUAL'},
    ];

    final body = {
      'page': 1,
      'limit': 1000,
      'clausulas': clausulas,
      'agregadores': [
        {'campo': 'descrdivisao', 'label': 'quantidade', 'agregador': 'COUNT'},
      ],
    };

    final response = await apiClient.postService(
      'insights/produtos_sem_venda',
      body: body,
    );

    if (response == null || response['data'] == null || response['data'] is! List) {
      print("⚠️ resposta inválida ao resumir por divisão");
      return [];
    }

    return (response['data'] as List).map((e) {
      final item = e as Map<String, dynamic>;
      return {
        'iddivisao': item['iddivisao'],
        'divisao': item['descrdivisao'],
        'quantidade': (item['quantidade'] as num).toInt(),
      };
    }).toList();
  }
}

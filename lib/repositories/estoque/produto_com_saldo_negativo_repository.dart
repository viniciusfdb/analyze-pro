import 'package:analyzepro/api/api_client.dart';
import '../../models/estoque/produto_com_saldo_negativo_model.dart';

class ProdutoComSaldoNegativoRepository {
  final ApiClient apiClient;

  ProdutoComSaldoNegativoRepository(this.apiClient);

  /// 🔹 Busca os produto com saldo negativo com base nos filtros aplicados
  Future<List<ProdutoComSaldoNegativo>> getProdutoComSaldoNegativo({
    required List<int> empresas,
    required String dataFim, // formato yyyy-MM-dd
    String flagInativo = 'F',
  }) async {
    try {
      int page = 1;
      bool hasNext = true;
      List<ProdutoComSaldoNegativo> resultados = [];

      while (hasNext) {
        final List<Map<String, dynamic>> clausulas = [
          {
            'campo': 'ra_idempresa',
            'valor': empresas,
            'operadorlogico': 'AND',
            'operador': 'IN',
          },
          {
            'campo': 'ra_dtfim',
            'valor': [dataFim],
            'operadorlogico': 'AND',
            'operador': 'IGUAL',
          },
          {
            'campo': 'ra_flaginativo',
            'valor': [flagInativo],
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
          'insights/saldos_negativos',
          body: body,
        );

        if (response == null || response['data'] == null || !(response['data'] is List)) {
          print("⚠️ resposta inválida na página $page");
          break;
        }

        final List data = response['data'] as List;
        for (var item in data) {
          try {
            resultados.add(ProdutoComSaldoNegativo.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            print("❌ falha ao converter item: $e, dado: $item");
          }
        }

        hasNext = response['hasNext'] == true;
        page++;
      }

      return resultados;
    } catch (e) {
      print("❌ Erro ao buscar produto com saldo negativo: $e");
      return [];
    }
  }
}
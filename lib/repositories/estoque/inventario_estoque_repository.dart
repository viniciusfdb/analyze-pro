import '../../api/api_client.dart';
import '../../models/estoque/inventario_estoque_model.dart';

class InventarioEstoqueRepository {
  final ApiClient apiClient;

  InventarioEstoqueRepository(this.apiClient);

  /// Retorna dados do inventário de estoque sem filtro de empresa
  Future<List<InventarioEstoque>> getInventarioEstoque({int? empresa}) async {
    int page = 1;
    const int limit = 1000;
    List<InventarioEstoque> allData = [];
    final clausulas = <Map<String, dynamic>>[];

    if (empresa != null) {
      clausulas.add({
        'campo': 'idempresa',
        'valor': empresa,
        'operadorlogico': 'AND',
        'operador': 'IGUAL',
      });
    }

    while (true) {
      final response = await apiClient.postService(
        'insights/inventario_estoque',
        body: {
          'page': page,
          'limit': limit,
        'clausulas': clausulas,
        },
      );

      if (response == null || !response.containsKey('data')) {
        print("⚠️ [ALERTA] API retornou resposta vazia ou inválida");
        break;
      }

      final List<dynamic> dataList = response['data'];
      if (dataList.isEmpty) break;

      for (var json in dataList) {
        try {
          var item = InventarioEstoque.fromJson(json);
          allData.add(item);
        } catch (e) {
          print("❌ Erro ao processar registro: $e");
        }
      }

      if (!(response['hasNext'] ?? false)) break;
      page++;
    }

    print("✅ Total de registros carregados: ${allData.length}");
    return allData;
  }
}
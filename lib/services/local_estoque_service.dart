import 'package:analyzepro/api/api_client.dart';

class LocalEstoqueService {
  final ApiClient apiClient;

  LocalEstoqueService(this.apiClient);

  /// 🔹 Obtém a lista de locais de estoque disponíveis
  Future<List<Map<String, dynamic>>> getLocaisEstoque() async {
    try {
      final response = await apiClient.postService('insights/local_estoque', body: {});

      if (response == null || !response.containsKey('data')) {
        print("⚠️ API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> locais = response['data'];
      return locais.map<Map<String, dynamic>>((e) {
        return {
          'idlocalestoque': e['idlocalestoque'] ?? 0,
          'descrlocal': e['descrlocal'] ?? 'Sem Nome',
        };
      }).toList();
    } catch (e) {
      print("❌ Erro ao buscar locais de estoque: $e");
      return [];
    }
  }
}

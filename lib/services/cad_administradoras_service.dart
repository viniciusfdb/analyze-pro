import '../api/api_client.dart';

class CadAdministradorasService {
  final ApiClient apiClient;

  // Cache das administradoras
  List<Map<String, dynamic>> _cachedAdministradoras = [];

  CadAdministradorasService(this.apiClient);

  /// 🔹 Obtém a lista de administradoras disponíveis
  Future<List<Map<String, dynamic>>> getAdministradorasDisponiveis() async {
    // Limpa o cache ao alterar a conexão
    _cachedAdministradoras = [];

    try {
      final response = await apiClient.postService(
        'insights/cad_administradoras', // Endpoint correto
        body: {
          'page': 1,
          'limit': 100,
        },
      );

      if (response == null || !response.containsKey('data') || response['data'].isEmpty) {
        print("⚠️ [ALERTA] API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> administradoras = response['data'];
      _cachedAdministradoras = administradoras.map((e) {
        return {
          'id': e['idadministradora'] ?? 0,
          'descricao': e['descradministradora'] ?? '',
        };
      }).toList();

      print("🔹 Administradoras carregadas: ${_cachedAdministradoras.length}");

      return _cachedAdministradoras;
    } catch (e) {
      print("❌ Erro ao buscar administradoras: $e");
      return [];
    }
  }

  /// 🔹 Limpa o cache de administradoras
  void clearCachedAdministradoras() {
    _cachedAdministradoras = [];
    print("🔹 Cache de administradoras limpo.");
  }
}

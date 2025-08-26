import '../api/api_client.dart';
import '../models/cadastros/cad_lojas.dart';
// Se necessário, adicione para gerenciar o armazenamento seguro

class CadLojasService {
  final ApiClient apiClient;

  // Variável que armazena o cache de empresas
  List<int> _cachedEmpresas = [];

  CadLojasService(this.apiClient);

  // Método para obter empresas disponíveis
  Future<List<int>> getEmpresasDisponiveis() async {
    // Limpa o cache ao alterar a conexão
    _cachedEmpresas = [];

    try {
      final response = await apiClient.postService(
        'cad_lojas', // Endpoint para obter empresas
        body: {},
      );

      if (response == null || !response.containsKey('data') || response['data'].isEmpty) {
        print("⚠️ [ALERTA] API retornou resposta vazia ou inválida");
        return []; // Retorna uma lista vazia em vez de null
      }

      final List<dynamic> empresas = response['data'];
      _cachedEmpresas = empresas
          .map<int>((e) => e['idempresa'] != null ? e['idempresa'] as int : 0)
          .where((id) => id > 0) // Filtra empresas válidas
          .toList();

      print("🔹 Empresas carregadas: $_cachedEmpresas");

      return _cachedEmpresas..sort();
    } catch (e) {
      print("❌ Erro ao buscar empresas: $e");
      return []; // Retorna uma lista vazia em caso de erro
    }
  }

  Future<List<Empresa>> getEmpresasComNome() async {
    try {
      final response = await apiClient.postService(
        'cad_lojas',
        body: {},
      );

      if (response == null || !response.containsKey('data') || response['data'].isEmpty) {
        print("⚠️ [ALERTA] API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> empresas = response['data'];
      final empresasComNome = empresas
          .map<Empresa>((e) => Empresa.fromMap(e))
          .where((e) => e.id > 0)
          .toList();

      // ===== TRECHO TEMPORÁRIO PARA GRAVAÇÃO DE VÍDEO =====
      // Substitui os nomes reais das lojas por "Loja exemplo X".
      // REMOVA este bloco após finalizar a gravação do vídeo.

      // for (var i = 0; i < empresasComNome.length; i++) {
       // final emp = empresasComNome[i];
        // empresasComNome[i] = Empresa(id: emp.id, nome: 'Loja exemplo ${i + 1}');
      // }
      // ===== FIM DO TRECHO TEMPORÁRIO =====

      print("🔹 Empresas com nome carregadas: $empresasComNome");

      return empresasComNome..sort((a, b) => a.id.compareTo(b.id));
    } catch (e) {
      print("❌ Erro ao buscar empresas com nome: $e");
      return [];
    }
  }

  Future<Empresa?> getEmpresaPorId(int id) async {
    try {
      final response = await apiClient.postService(
        'cad_lojas',
        body: {
          "page": 1,
          "limit": 1,
          "clausulas": [
            {
              "campo": "idempresa",
              "valor": id,
              "operador": "IGUAL",
              "operadorLogico": "AND"
            }
          ]
        },
      );

      if (response == null || !response.containsKey('data') || response['data'].isEmpty) {
        print("⚠️ Empresa com id $id não encontrada.");
        return null;
      }

      final empresaJson = response['data'][0];
      return Empresa.fromMap(empresaJson);
    } catch (e) {
      print("❌ Erro ao buscar empresa por ID: $e");
      return null;
    }
  }

  // Limpa o cache de empresas
  void clearCachedEmpresas() {
    _cachedEmpresas = [];
    print("🔹 Cache de empresas limpo.");
  }

  Future<List<Empresa>> fetchAll() async {
    try {
      final response = await apiClient.postService('cad_lojas', body: {});
      if (response == null || !response.containsKey('data') || response['data'].isEmpty) {
        print("⚠️ [ALERTA] API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> data = response['data'];
      return data.map<Empresa>((e) => Empresa.fromMap(e)).toList();
    } catch (e) {
      print("❌ Erro ao buscar todas as empresas: $e");
      return [];
    }
  }
}

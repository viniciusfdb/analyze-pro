import 'package:flutter/cupertino.dart';
import '../api/api_client.dart';

class CadProdutosService {
  final ApiClient apiClient;

  CadProdutosService(this.apiClient);

  // 🔹 Obtém divisões disponíveis
  Future<List<Map<String, dynamic>>> getDivisoes() async {
    try {
      final response = await apiClient.postService('cad_produtos', body: {});
      if (response == null || !response.containsKey('data')) {
        print("⚠️ API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> divisoes = response['data'];
      return divisoes.map<Map<String, dynamic>>((e) {
        return {
          'id': e['iddivisao'] ?? 0,
          'descricao': e['descrdivisao'] ?? '',
        };
      }).toList();
    } catch (e) {
      print("❌ Erro ao buscar divisões: $e");
      return [];
    }
  }

  // 🔹 Obtém seções disponíveis
  Future<List<Map<String, dynamic>>> getSecoesDisponiveis(int iddivisao) async {
    try {
      final response = await apiClient.postService(
        'cad_produtos',
        body: {'iddvisao': iddivisao}, // Filtra pelas divisões selecionadas
      );

      if (response == null || !response.containsKey('data')) {
        debugPrint("⚠️ API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> secoes = response['data'];
      return secoes.map<Map<String, dynamic>>((e) {
        return {
          'idsecao': e['idsecao'] ?? 0,  // 🔹 Corrigido para minúsculas
          'descrsecao': e['descrsecao'] ?? 'Sem Nome',  // 🔹 Corrigido para minúsculas
        };
      }).toList();
    } catch (e) {
      debugPrint("❌ Erro ao buscar seções: $e");
      return [];
    }
  }


  // 🔹 Obtém grupos disponíveis
  Future<List<Map<String, dynamic>>> getGrupos(int idsecao) async {
    try {
      final response = await apiClient.postService(
        'cad_produtos',
        body: {'idsecao': idsecao}, // Filtra pelas seções selecionadas
      );

      if (response == null || !response.containsKey('data')) {
        print("⚠️ API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> grupos = response['data'];
      return grupos.map<Map<String, dynamic>>((e) {
        return {
          'id': e['idgrupo'] ?? 0,
          'descricao': e['descrgrupo'] ?? '',
        };
      }).toList();
    } catch (e) {
      print("❌ Erro ao buscar grupos: $e");
      return [];
    }
  }

  // 🔹 Obtém subgrupos disponíveis
  Future<List<Map<String, dynamic>>> getSubGrupos(int idgrupo) async {
    try {
      final response = await apiClient.postService(
        'cad_produtos',
        body: {'idgrupo': idgrupo}, // Filtra pelos grupos selecionados
      );

      if (response == null || !response.containsKey('data')) {
        print("⚠️ API retornou resposta vazia ou inválida");
        return [];
      }

      final List<dynamic> subGrupos = response['data'];
      return subGrupos.map<Map<String, dynamic>>((e) {
        return {
          'id': e['idsubgrupo'] ?? 0,
          'descricao': e['descrsubgrupo'] ?? '',
        };
      }).toList();
    } catch (e) {
      print("❌ Erro ao buscar subgrupos: $e");
      return [];
    }
  }
}

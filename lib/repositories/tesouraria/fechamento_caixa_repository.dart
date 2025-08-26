import 'package:intl/intl.dart';
import '../../api/api_client.dart';
import '../../models/tesouraria/fechamento_caixa.dart';

class FechamentoCaixaRepository {
  final ApiClient apiClient;

  // Cache de empresas
  List<int> _cachedEmpresas = [];

  FechamentoCaixaRepository(this.apiClient);

  /// 🔹 Retorna registros de fechamento de caixa filtrados por uma única data e idempresa
  Future<List<FechamentoCaixa>> getFechamentoCaixa({
    required String data,
    required String empresa,
  }) async {
    int page = 1;
    const int limit = 1000;
    List<FechamentoCaixa> allData = [];

    while (true) {
      final response = await apiClient.postService(
        'insights/fechamento_caixa',
        body: {
          'page': page,
          'limit': limit,
          'clausulas': [
            {
              'campo': 'idempresa',
              'valor': empresa,
              'operadorlogico': 'AND',
              'operador': 'IGUAL'
            },
            {
              'campo': 'dtmovimento',
              'valor': data,
              'operadorlogico': 'AND',
              'operador': 'IGUAL'
            }
          ]
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
          var item = FechamentoCaixa.fromJson(json);
          allData.add(item);
        } catch (e) {
          print("❌ Erro ao processar registro: $e");
        }
      }

      final bool hasNext = response['hasNext'] == true;
      if (!hasNext) break;
      page++; // Aumenta a página para carregar os próximos registros
    }

    print("✅ Total de registros carregados: ${allData.length}");
    return allData;
  }

  /// 🔹 Retorna todas as empresas disponíveis sem precisar processar tudo localmente
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
        return [];
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
      return [];
    }
  }

  /// 🔹 Limpa o cache de empresas
  void clearCachedEmpresas() {
    _cachedEmpresas = [];
    print("🔹 Cache de empresas limpo.");
  }

  Future<Map<String, dynamic>> getFechamentoCaixaFiltrado(int idempresa, DateTime dataSelecionada) async {
    final String dataFiltro = DateFormat('yyyy-MM-dd').format(dataSelecionada); // Formata a data para o formato correto

    final List<FechamentoCaixa> allData = await getFechamentoCaixa(
      data: dataFiltro, // Passa a data única como filtro
      empresa: idempresa.toString(), // Passa o ID da empresa como filtro
    );

    List<FechamentoCaixa> registrosFiltrados = [];
    double totalSobras = 0.0;
    double totalFaltas = 0.0;

    for (var fech in allData) {
      registrosFiltrados.add(fech);

      if (fech.valResultado > 0) {
        totalSobras += fech.valResultado;
      } else if (fech.valResultado < 0) {
        totalFaltas += fech.valResultado.abs();
      }
    }

    return {
      "registros": registrosFiltrados,
      "totalSobras": totalSobras,
      "totalFaltas": totalFaltas,
    };
  }
}

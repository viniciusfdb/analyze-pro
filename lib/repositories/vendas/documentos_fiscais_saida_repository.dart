import 'package:intl/intl.dart';
import '../../api/api_client.dart';
import '../../models/vendas/documentos_fiscais_saida.dart';
import '../../models/vendas/documentos_fiscais_saida_resumo.dart';

class DocumentosFiscaisSaidaRepository {
  final ApiClient apiClient;

  DocumentosFiscaisSaidaRepository(this.apiClient);

  /// Retorna lista completa de documentos fiscais de saída.
  Future<List<DocumentosFiscaisSaida>> getDocumentosFiscaisSaida({
    int? empresa,
    DateTime? dtMovimento,
    DateTime? dtMovimentoInicio,
    DateTime? dtMovimentoFim,
    String? tipoNota,
    Map<String, int>? paginacao,
  }) async {
    int page = 1;
    int limit = 100;
    if (dtMovimentoInicio != null && dtMovimentoFim != null) {
      // Esses valores podem ser sobrescritos por parâmetros se forem passados via chamada
      page = paginacao?['page'] ?? 1;
      limit = paginacao?['limit'] ?? 100;
    }
    final clausulas = <Map<String, dynamic>>[];

    if (empresa != null) {
      clausulas.add({
        'campo': 'idempresa',
        'valor': empresa,
        'operadorlogico': 'AND',
        'operador': 'IGUAL',
      });
    }
    if (dtMovimento != null) {
      clausulas.add({
        'campo': 'dtmovimento',
        'valor': DateFormat('yyyy-MM-dd').format(dtMovimento),
        'operadorlogico': 'AND',
        'operador': 'IGUAL',
      });
    }
    if (dtMovimentoInicio != null && dtMovimentoFim != null) {
      clausulas.add({
        'campo': 'dtmovimento',
        'valor': [
          DateFormat('yyyy-MM-dd').format(dtMovimentoInicio),
          DateFormat('yyyy-MM-dd').format(dtMovimentoFim),
        ],
        'operadorlogico': 'AND',
        'operador': 'BETWEEN',
      });
    }
    if (tipoNota != null && tipoNota.isNotEmpty) {
      clausulas.add({
        'campo': 'tiponota',
        'valor': tipoNota,
        'operadorlogico': 'AND',
        'operador': 'IGUAL',
      });
    }

    final List<DocumentosFiscaisSaida> allData = [];
    while (true) {
      final response = await apiClient.postService(
        'documentos_fiscais_saida',
        body: {
          'page': page,
          'limit': limit,
          'clausulas': clausulas,
        },
      );

      print('📥 Página $page recebida com ${response['data']?.length ?? 0} registros');

      if (response == null || !response.containsKey('data')) break;
      final dataList = response['data'] as List<dynamic>;
      if (dataList.isEmpty) break;

      for (var json in dataList) {
        try {
          allData.add(DocumentosFiscaisSaida.fromJson(json));
        } catch (e) {
          print('❌ Erro ao processar documento: $e');
        }
      }
      if (!(response['hasNext'] ?? false)) break;
      page++;
    }
    print('✅ Total de documentos carregados: ${allData.length}');
    return allData;
  }

  /// Retorna só o resumo (qtd + soma do valor) usando agregadores
  Future<DocumentosFiscaisSaidaResumo> getResumoDocumentosFiscaisSaida({
    int? empresa,
    DateTime? dtMovimentoInicio,
    DateTime? dtMovimentoFim,
    String? tipoNota,
  }) async {
    final body = {
      'page': 1,
      'limit': 1,
      'clausulas': [
        {
          'campo': 'dtmovimento',
          'valor': [
            // default to start-of-day
            "${DateFormat('yyyy-MM-dd').format(dtMovimentoInicio ?? DateTime.now())}T00:00:00",
            // default to end-of-day
            "${DateFormat('yyyy-MM-dd').format(dtMovimentoFim ?? DateTime.now())}T23:59:59",
          ],
          'operadorlogico': 'AND',
          'operador': 'BETWEEN'
        },
        if (empresa != null)
          {
            'campo': 'idempresa',
            'valor': empresa.toString(),
            'operadorlogico': 'AND',
            'operador': 'IGUAL'
          },
        {
          'campo': 'flagnotacancel',
          'valor': 'F',
          'operadorlogico': 'AND',
          'operador': 'IGUAL'
        },
        if (tipoNota != null && tipoNota.isNotEmpty)
          {
            'campo': 'tiponota',
            'valor': tipoNota,
            'operadorlogico': 'AND',
            'operador': 'IGUAL'
          },
      ],
      'agregadores': [
        {
          'campo': 0,
          'label': 'qtd',
          'agregador': 'COUNT'
        },
        {
          'campo': 'valcontabil',
          'label': 'soma_valor_liq_doc_saida',
          'agregador': 'SUM'
        }
      ],
      'ordenacoes': [
        {
          'campo': 'idplanilha',
          'direcao': 'ASC'
        },
        {
          'campo': 'idempresa',
          'direcao': 'ASC'
        }
      ]
    };

    final response = await apiClient.postService('documentos_fiscais_saida', body: body);
    if (response == null || !response.containsKey('data') || (response['data'] as List).isEmpty) {
      throw Exception('Resumo vazio ou inválido');
    }

    final resumoJson = (response['data'] as List).first as Map<String, dynamic>;
    return DocumentosFiscaisSaidaResumo.fromJson(resumoJson);
  }

  Future<List<Map<String, dynamic>>> ticketMedioDiario({
    required int? idEmpresa,
    required DateTime dtInicio,
    required DateTime dtFim,
  }) async {
    final List<Map<String, dynamic>> resultado = [];
    final dateFmt = DateFormat('yyyy-MM-dd');

    // garante ordem cronológica e percorre cada dia do intervalo
    for (DateTime dia = dtInicio;
        !dia.isAfter(dtFim);
        dia = dia.add(const Duration(days: 1))) {
      try {
        // Usa o resumo diário (total vendas e qtd de itens)
        final resumo = await getResumoDocumentosFiscaisSaida(
          empresa: idEmpresa,
          dtMovimentoInicio: dia,
          dtMovimentoFim: dia,
          tipoNota: 'S', // considera apenas Saída (ignora devolução)
        );

        final qtd   = resumo.qtd;
        final valor = resumo.somaValorLiqDocSaida;

        final ticket = qtd == 0 ? 0.0 : valor / qtd;

        resultado.add({
          'date': dateFmt.format(dia),
          'valor': ticket,
        });
      } catch (e) {
        // Se falhar (ex: sem dados), registra ticket 0 para manter consistência
        resultado.add({
          'date': dateFmt.format(dia),
          'valor': 0.0,
        });
        print('⚠️ Falha ao calcular Ticket Médio para ${dateFmt.format(dia)}: $e');
      }
    }

    return resultado;
  }

  vendasPorEmpresa({required idEmpresa, required DateTime dtInicio, required DateTime dtFim}) {}

  Future<List<DocumentosFiscaisSaida>> getDocumentosFiscaisSaidaPaginado({
    required int limit,
    required int page,
    DateTime? dataInicial,
    DateTime? dataFinal,
  }) async {
    final clausulas = <Map<String, dynamic>>[];

    if (dataInicial != null && dataFinal != null) {
      clausulas.add({
        'campo': 'dtmovimento',
        'valor': [
          dataInicial.toIso8601String().split("T")[0],
          dataFinal.toIso8601String().split("T")[0],
        ],
        'operadorlogico': 'AND',
        'operador': 'BETWEEN',
      });
    }

    final response = await apiClient.postService(
      'documentos_fiscais_saida',
      body: {
        'page': page,
        'limit': limit,
        if (clausulas.isNotEmpty) 'clausulas': clausulas,
      },
    );

    if (response == null || !response.containsKey('data')) {
      return [];
    }

    final List<dynamic> dataList = response['data'];
    final List<DocumentosFiscaisSaida> result = [];

    for (var json in dataList) {
      try {
        result.add(DocumentosFiscaisSaida.fromJson(json));
      } catch (e) {
        print('❌ Erro ao converter documento fiscal: $e');
      }
    }

    return result;
  }
}
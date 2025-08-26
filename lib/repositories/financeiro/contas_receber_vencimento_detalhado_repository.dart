

import 'package:analyzepro/api/api_client.dart';
import '../../models/financeiro/contas_receber_vencimento_detalhado.dart';

class ContasReceberVencimentoDetalhadoRepository {
  final ApiClient api;

  ContasReceberVencimentoDetalhadoRepository(this.api);

  Future<List<ContasReceberVencimentoDetalhadoModel>> getDetalhamento({
    required int idEmpresa,
    required DateTime dataInicial,
    required DateTime dataFinal,
    int? idRecebimento,
  }) async {
    final clausulas = [
      {
        "campo": "ra_idempresa",
        "valor": idEmpresa,
        "operador": "IGUAL",
      },
      {
        "campo": "ra_dtini",
        "valor": dataInicial.toIso8601String().split('T').first,
        "operador": "IGUAL",
      },
      {
        "campo": "ra_dtfim",
        "valor": dataFinal.toIso8601String().split('T').first,
        "operador": "IGUAL",
      },
    ];

    if (idRecebimento != null) {
      clausulas.add({
        "campo": "idrecebimento",
        "valor": idRecebimento,
        "operador": "IGUAL",
        "operadorLogico": "AND",
      });
    }

    final response = await api.postService(
      'insights/contas_receber_vencimento_detalhado',
      body: {
        "page": 1,
        "limit": 1000,
        "clausulas": clausulas,
      },
    );

    final lista = response['data'] as List<dynamic>;
    return lista
        .map((json) => ContasReceberVencimentoDetalhadoModel.fromJson(json))
        .toList();
  }
}
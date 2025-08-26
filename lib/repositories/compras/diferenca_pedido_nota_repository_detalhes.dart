import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import '../../models/compras/diferenca_pedido_nota_model_detalhes.dart';

/// Repositório que consome o serviço
/// **insights/diferenca_pedido_nota_detalhes**
class DiferencaPedidoNotaDetalhesRepository {
  final ApiClient _api;
  final DateFormat _fmt = DateFormat('yyyy-MM-dd');

  DiferencaPedidoNotaDetalhesRepository(this._api);

  /// Recupera a lista de itens divergentes (pedido × nota) para um
  /// fornecedor específico em um intervalo de datas.
  Future<List<DiferencaPedidoNotaDetalhesModel>> fetchDetalhes({
    required int idEmpresa,
    required int idClifor,
    required double valorMinDif,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final body = {
      "page": 1,
      "limit": 1000,
      "clausulas": [
        {
          "campo": "ra_idempresa",
          "valor": idEmpresa,
          "operador": "IGUAL",
        },
        {
          "campo": "ra_idclifor",
          "valor": idClifor.toString(),
          "operador": "IGUAL",
        },
        {
          "campo": "ra_valor_min_dif",
          "valor": valorMinDif.toString(),
          "operador": "IGUAL",
        },
        {
          "campo": "ra_dtini",
          "valor": _fmt.format(dataInicial),
          "operador": "IGUAL",
        },
        {
          "campo": "ra_dtfim",
          "valor": _fmt.format(dataFinal),
          "operador": "IGUAL",
        },
      ],
    };

    final resp = await _api.postService(
      'insights/diferenca_pedido_nota_detalhes',
      body: body,
    );

    final lista = (resp['data'] as List<dynamic>)
        .map((e) => DiferencaPedidoNotaDetalhesModel.fromJson(
              e as Map<String, dynamic>,
            ))
        .toList();

    return lista;
  }
}
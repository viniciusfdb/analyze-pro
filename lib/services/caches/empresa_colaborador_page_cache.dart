import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/models/vendas/empresa_colaborador.dart';
import 'package:analyzepro/models/vendas/faturamento_com_lucro_model.dart';

/// Entrada serializável do resumo (equivalente a _EmpresaResumo)
class EmpresaResumoCacheEntry {
  final Empresa empresa;
  final int colaboradores;
  final FaturamentoComLucro? fat;

  EmpresaResumoCacheEntry({
    required this.empresa,
    required this.colaboradores,
    required this.fat,
  });
}

/// Cache singleton da página Empresa x Colaborador
class EmpresaColaboradorPageCache {
  EmpresaColaboradorPageCache._();
  static final EmpresaColaboradorPageCache instance = EmpresaColaboradorPageCache._();

  List<EmpresaResumoCacheEntry>? resumos;
  FaturamentoComLucro? faturamento;
  EmpresaColaborador? colaborador;
  int? qtdManual;
  Empresa? empresaSelecionada;
  int? ano;
  int? mes;
  DateTime? timestamp;
  double? tempoMedioEstimado;

  static const _ttlMin = 30;

  bool get cacheValido =>
      timestamp != null &&
          DateTime.now().difference(timestamp!).inMinutes < _ttlMin &&
          resumos != null &&
          resumos!.isNotEmpty;

  void salvar({
    required List<EmpresaResumoCacheEntry> resumos,
    FaturamentoComLucro? faturamento,
    EmpresaColaborador? colaborador,
    int? qtdManual,
    required Empresa? empresaSelecionada,
    required int ano,
    required int mes,
    double? tempoMedioEstimado,
  }) {
    this.resumos = resumos;
    this.faturamento = faturamento;
    this.colaborador = colaborador;
    this.qtdManual = qtdManual;
    this.empresaSelecionada = empresaSelecionada;
    this.ano = ano;
    this.mes = mes;
    this.tempoMedioEstimado = tempoMedioEstimado;
    timestamp = DateTime.now();
  }

  void limpar() {
    resumos = null;
    faturamento = null;
    colaborador = null;
    qtdManual = null;
    empresaSelecionada = null;
    ano = null;
    mes = null;
    timestamp = null;
    tempoMedioEstimado = null;
  }
}
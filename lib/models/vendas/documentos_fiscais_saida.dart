class DocumentosFiscaisSaida {
  final int idEmpresa;
  final int idPlanilha;
  final int idCliFor;
  final int idCaixa;
  final int idVendedor;
  final String nomeCliente;
  final int numNota;
  final String serieNota;
  final String modelo;
  final double valContabil;
  final double valDescontoFinanceiro;
  final double valAcrescimoFinanceiro;
  final double valImpostos;
  final double valFreteNota;
  final DateTime dtMovimento;
  final String chaveNFe;
  final String tipoNota;
  final DateTime dtEmissao;
  final String codigoExterno;
  final int idFormaPgto;
  final String descrFormaPgto;
  final double valTitulo;
  final int idUsuario;
  final String nomeUsuario;
  final String cpfVendedor;
  final int coo;
  final String numSerieImpres;
  final int truncRound;
  final String flagNotaCancel;
  final DateTime? dtCancelamento;
  final DateTime dtAlteracao;
  final int? idOrcamento;
  final String cnpjCpf;

  DocumentosFiscaisSaida({
    required this.idEmpresa,
    required this.idPlanilha,
    required this.idCliFor,
    required this.idCaixa,
    required this.idVendedor,
    required this.nomeCliente,
    required this.numNota,
    required this.serieNota,
    required this.modelo,
    required this.valContabil,
    required this.valDescontoFinanceiro,
    required this.valAcrescimoFinanceiro,
    required this.valImpostos,
    required this.valFreteNota,
    required this.dtMovimento,
    required this.chaveNFe,
    required this.tipoNota,
    required this.dtEmissao,
    required this.codigoExterno,
    required this.idFormaPgto,
    required this.descrFormaPgto,
    required this.valTitulo,
    required this.idUsuario,
    required this.nomeUsuario,
    required this.cpfVendedor,
    required this.coo,
    required this.numSerieImpres,
    required this.truncRound,
    required this.flagNotaCancel,
    this.dtCancelamento,
    required this.dtAlteracao,
    this.idOrcamento,
    required this.cnpjCpf,
  });

  factory DocumentosFiscaisSaida.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String? s) =>
        s == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.parse(s);

    return DocumentosFiscaisSaida(
      idEmpresa: (json['idempresa'] ?? 0) as int,
      idPlanilha: (json['idplanilha'] ?? 0) as int,
      idCliFor: (json['idclifor'] ?? 0) as int,
      idCaixa: (json['idcaixa'] ?? 0) as int,
      idVendedor: (json['idvendedor'] ?? 0) as int,
      nomeCliente: json['nome'] as String? ?? '',
      numNota: (json['numnota'] ?? 0) as int,
      serieNota: json['serienota'] as String? ?? '',
      modelo: json['modelo'] as String? ?? '',
      valContabil: double.tryParse(json['valcontabil']?.toString() ?? '0') ?? 0,
      valDescontoFinanceiro: double.tryParse(json['valdescontofinanceiro']?.toString() ?? '0') ?? 0,
      valAcrescimoFinanceiro: double.tryParse(json['valacrescimofinanceiro']?.toString() ?? '0') ?? 0,
      valImpostos: double.tryParse(json['valimpostos']?.toString() ?? '0') ?? 0,
      valFreteNota: double.tryParse(json['valfretenota']?.toString() ?? '0') ?? 0,
      dtMovimento: parseDate(json['dtmovimento'] as String?),
      chaveNFe: json['chavenfe'] as String? ?? '',
      tipoNota: json['tiponota'] as String? ?? '',
      dtEmissao: parseDate(json['dtemissao'] as String?),
      codigoExterno: json['codigoexterno'] as String? ?? '',
      idFormaPgto: int.tryParse(json['idformapgto']?.toString() ?? '0') ?? 0,
      descrFormaPgto: json['descrformapgto'] as String? ?? '',
      valTitulo: double.tryParse(json['valtitulo']?.toString() ?? '0') ?? 0,
      idUsuario: (json['idusuario'] ?? 0) as int,
      nomeUsuario: json['nomeusuario'] as String? ?? '',
      cpfVendedor: json['cpfvendedor'] as String? ?? '',
      coo: (json['coo'] ?? 0) as int,
      numSerieImpres: json['numserieimpres'] as String? ?? '',
      truncRound: (json['truncround'] ?? 0) as int,
      flagNotaCancel: json['flagnotacancel'] as String? ?? '',
      dtCancelamento: json['dtcancelamento'] != null
          ? DateTime.parse(json['dtcancelamento'])
          : null,
      dtAlteracao: parseDate(json['dtalteracao'] as String?),
      idOrcamento: json['idorcamento'] != null ? (json['idorcamento'] as num).toInt() : null,
      cnpjCpf: json['cnpjcpf'] as String? ?? '',
    );
  }
}
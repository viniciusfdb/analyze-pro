class DocumentoFiscalEntrada {
  final int idEmpresa;
  final int idPlanilha;
  final int idClifor;
  final String nome;
  final int numNota;
  final String serieNota;
  final String modelo;
  final String uf;
  final double valContabil;
  final double valImpostos;
  final double valDescontoFinanceiro;
  final double valAcrescimoFinanceiro;
  final double valFreteNota;
  final DateTime dtEmissao;
  final DateTime dtMovimento;
  final String chaveNfe;
  final String tipoNota;
  final DateTime dtAlteracao;
  final String cnpjCpf;
  final String chaveNfeOrigem;

  DocumentoFiscalEntrada({
    required this.idEmpresa,
    required this.idPlanilha,
    required this.idClifor,
    required this.nome,
    required this.numNota,
    required this.serieNota,
    required this.modelo,
    required this.uf,
    required this.valContabil,
    required this.valImpostos,
    required this.valDescontoFinanceiro,
    required this.valAcrescimoFinanceiro,
    required this.valFreteNota,
    required this.dtEmissao,
    required this.dtMovimento,
    required this.chaveNfe,
    required this.tipoNota,
    required this.dtAlteracao,
    required this.cnpjCpf,
    required this.chaveNfeOrigem,
  });

  factory DocumentoFiscalEntrada.fromMap(Map<String, dynamic> map) {
    return DocumentoFiscalEntrada(
      idEmpresa: map['idempresa'] ?? 0,
      idPlanilha: map['idplanilha'] ?? 0,
      idClifor: map['idclifor'] ?? 0,
      nome: map['nome'] ?? '',
      numNota: map['numnota'] ?? 0,
      serieNota: map['serienota'] ?? '',
      modelo: map['modelo'] ?? '',
      uf: map['uf'] ?? '',
      valContabil: (map['valcontabil'] ?? 0).toDouble(),
      valImpostos: (map['valimpostos'] ?? 0).toDouble(),
      valDescontoFinanceiro: (map['valdescontofinanceiro'] ?? 0).toDouble(),
      valAcrescimoFinanceiro: (map['valacrescimofinanceiro'] ?? 0).toDouble(),
      valFreteNota: (map['valfretenota'] ?? 0).toDouble(),
      dtEmissao: DateTime.tryParse(map['dtemissao'] ?? '') ?? DateTime(2000),
      dtMovimento: DateTime.tryParse(map['dtmovimento'] ?? '') ?? DateTime(2000),
      chaveNfe: map['chavenfe'] ?? '',
      tipoNota: map['tiponota'] ?? '',
      dtAlteracao: DateTime.tryParse(map['dtalteracao'] ?? '') ?? DateTime(2000),
      cnpjCpf: map['cnpjcpf'] ?? '',
      chaveNfeOrigem: map['chavenfeorigem'] ?? '',
    );
  }
}
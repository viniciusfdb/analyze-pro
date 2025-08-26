class ProdutoComSaldoNegativo {
  final int idempresa;
  final int iddivisao;
  final String descrdivisao;
  final int idsecao;
  final String descrsecao;
  final int idgrupo;
  final String descrgrupo;
  final int idsubgrupo;
  final String descrsubgrupo;
  final int idsubproduto;
  final String descricaoproduto;
  final int idlocalestoque;
  final double customedio;
  final double qtdatualestoque;
  final double saldocustomedio;
  final double saldovarejo;

  ProdutoComSaldoNegativo({
    required this.idempresa,
    required this.iddivisao,
    required this.descrdivisao,
    required this.idsecao,
    required this.descrsecao,
    required this.idgrupo,
    required this.descrgrupo,
    required this.idsubgrupo,
    required this.descrsubgrupo,
    required this.idsubproduto,
    required this.descricaoproduto,
    required this.idlocalestoque,
    required this.customedio,
    required this.qtdatualestoque,
    required this.saldocustomedio,
    required this.saldovarejo,
  });

  factory ProdutoComSaldoNegativo.fromJson(Map<String, dynamic> json) {
    return ProdutoComSaldoNegativo(
      idempresa: json['idempresa'] ?? 0,
      iddivisao: json['iddivisao'] ?? 0,
      descrdivisao: json['descrdivisao'] ?? '',
      idsecao: json['idsecao'] ?? 0,
      descrsecao: json['descrsecao'] ?? '',
      idgrupo: json['idgrupo'] ?? 0,
      descrgrupo: json['descrgrupo'] ?? '',
      idsubgrupo: json['idsubgrupo'] ?? 0,
      descrsubgrupo: json['descrsubgrupo'] ?? '',
      idsubproduto: json['idsubproduto'] ?? 0,
      descricaoproduto: json['descricaoproduto'] ?? '',
      idlocalestoque: json['idlocalestoque'] ?? 0,
      customedio: (json['customedio'] as num?)?.toDouble() ?? 0.0,
      qtdatualestoque: (json['qtdatualestoque'] as num?)?.toDouble() ?? 0.0,
      saldocustomedio: (json['saldocustomedio'] as num?)?.toDouble() ?? 0.0,
      saldovarejo: (json['saldovarejo'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempresa': idempresa,
      'iddivisao': iddivisao,
      'descrdivisao': descrdivisao,
      'idsecao': idsecao,
      'descrsecao': descrsecao,
      'idgrupo': idgrupo,
      'descrgrupo': descrgrupo,
      'idsubgrupo': idsubgrupo,
      'descrsubgrupo': descrsubgrupo,
      'idsubproduto': idsubproduto,
      'descricaoproduto': descricaoproduto,
      'idlocalestoque': idlocalestoque,
      'customedio': customedio,
      'qtdatualestoque': qtdatualestoque,
      'saldocustomedio': saldocustomedio,
      'saldovarejo': saldovarejo,
    };
  }
}
class ProdutoSemVenda {
  final int idempresa;
  final int idproduto;
  final int idlocalestoque;
  final String descrdivisao;
  final int iddivisao;
  final String descrsecao;
  final int idsecao;
  final String descrgrupo;
  final int idgrupo;
  final String descrsubgrupo;
  final int idsubgrupo;
  final int idsubproduto;
  final String descricao;
  final double qtdatualestoque;
  final int dias;
  final double valprecovarejo;
  final double custoultimacompra;
  final String dtultimavenda;

  ProdutoSemVenda({
    required this.idempresa,
    required this.idproduto,
    required this.idlocalestoque,
    required this.descrdivisao,
    required this.iddivisao,
    required this.descrsecao,
    required this.idsecao,
    required this.descrgrupo,
    required this.idgrupo,
    required this.descrsubgrupo,
    required this.idsubgrupo,
    required this.idsubproduto,
    required this.descricao,
    required this.qtdatualestoque,
    required this.dias,
    required this.valprecovarejo,
    required this.custoultimacompra,
    required this.dtultimavenda,
  });

  factory ProdutoSemVenda.fromJson(Map<String, dynamic> json) {
    return ProdutoSemVenda(
      idempresa: json['idempresa'] ?? 0,
      idproduto: json['idproduto'] ?? 0,
      idlocalestoque: json['idlocalestoque'] ?? 0,
      descrdivisao: json['descrdivisao'] ?? '',
      iddivisao: json['iddivisao'] ?? 0,
      descrsecao: json['descrsecao'] ?? '',
      idsecao: json['idsecao'] ?? 0,
      descrgrupo: json['descrgrupo'] ?? '',
      idgrupo: json['idgrupo'] ?? 0,
      descrsubgrupo: json['descrsubgrupo'] ?? '',
      idsubgrupo: json['idsubgrupo'] ?? 0,
      idsubproduto: json['idsubproduto'] ?? 0,
      descricao: json['descricao'] ?? '',
      qtdatualestoque: (json['qtdatualestoque'] as num?)?.toDouble() ?? 0.0,
      dias: json['dias'] ?? 0,
      valprecovarejo: (json['valprecovarejo'] as num?)?.toDouble() ?? 0.0,
      custoultimacompra: (json['custoultimacompra'] as num?)?.toDouble() ?? 0.0,
      dtultimavenda: json['dtultimavenda'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempresa': idempresa,
      'idproduto': idproduto,
      'idlocalestoque': idlocalestoque,
      'descrdivisao': descrdivisao,
      'iddivisao': iddivisao,
      'descrsecao': descrsecao,
      'idsecao': idsecao,
      'descrgrupo': descrgrupo,
      'idgrupo': idgrupo,
      'descrsubgrupo': descrsubgrupo,
      'idsubgrupo': idsubgrupo,
      'idsubproduto': idsubproduto,
      'descricao': descricao,
      'qtdatualestoque': qtdatualestoque,
      'dias': dias,
      'valprecovarejo': valprecovarejo,
      'custoultimacompra': custoultimacompra,
      'dtultimavenda': dtultimavenda,
    };
  }
}
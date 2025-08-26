class VendaPorProdutoModel {
  final int idProduto;
  final int idSubproduto;
  final String descricao;
  final double qtdProduto;
  final double qtdProdutoVenda;
  final double valTotLiquido;
  final double lucro;
  final String flagInativoCompra;

  double? percVendaTotal;
  double? percLucratividade;

  VendaPorProdutoModel({
    required this.idProduto,
    required this.idSubproduto,
    required this.descricao,
    required this.qtdProduto,
    required this.qtdProdutoVenda,
    required this.valTotLiquido,
    required this.lucro,
    required this.flagInativoCompra,
    this.percVendaTotal,
    this.percLucratividade,
  });

  factory VendaPorProdutoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorProdutoModel(
      idProduto: json['idproduto'] ?? 0,
      idSubproduto: json['idsubproduto'] ?? 0,
      descricao: json['descricao'] ?? '',
      qtdProduto: (json['qtdproduto'] ?? 0).toDouble(),
      qtdProdutoVenda: (json['qtdprodutovenda'] ?? 0).toDouble(),
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
      flagInativoCompra: json['flaginativocompra'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idproduto': idProduto,
      'idsubproduto': idSubproduto,
      'descricao': descricao,
      'qtdproduto': qtdProduto,
      'qtdprodutovenda': qtdProdutoVenda,
      'valtotliquido': valTotLiquido,
      'lucro': lucro,
      'flaginativocompra': flagInativoCompra,
    };
  }

  /// Método usado para somar os dados de várias empresas
  VendaPorProdutoModel copyWith({
    double? qtdProduto,
    double? qtdProdutoVenda,
    double? valTotLiquido,
    double? lucro,
    double? percVendaTotal,
    double? percLucratividade,
  }) {
    return VendaPorProdutoModel(
      idProduto: idProduto,
      idSubproduto: idSubproduto,
      descricao: descricao,
      qtdProduto: qtdProduto ?? this.qtdProduto,
      qtdProdutoVenda: qtdProdutoVenda ?? this.qtdProdutoVenda,
      valTotLiquido: valTotLiquido ?? this.valTotLiquido,
      lucro: lucro ?? this.lucro,
      flagInativoCompra: flagInativoCompra,
      percVendaTotal: percVendaTotal ?? this.percVendaTotal,
      percLucratividade: percLucratividade ?? this.percLucratividade,
    );
  }
}
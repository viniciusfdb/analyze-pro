class VendaPorVendedorProdutoModel {
  final int idProduto;
  final int idSubProduto;
  final String descricao;
  final double qtdProduto;
  final double qtdProdutoVenda;
  final double valTotLiquido;
  final double lucro;
  double? percVendaTotal;
  double? percLucratividade;
  final String flagInativoCompra;

  VendaPorVendedorProdutoModel({
    required this.idProduto,
    required this.idSubProduto,
    required this.descricao,
    required this.qtdProduto,
    required this.qtdProdutoVenda,
    required this.valTotLiquido,
    required this.lucro,
    this.percVendaTotal,
    this.percLucratividade,
    required this.flagInativoCompra,
  });

  factory VendaPorVendedorProdutoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorVendedorProdutoModel(
      idProduto: json['idproduto'],
      idSubProduto: json['idsubproduto'],
      descricao: json['descricao'],
      qtdProduto: (json['qtdproduto'] ?? 0).toDouble(),
      qtdProdutoVenda: (json['qtdprodutovenda'] ?? 0).toDouble(),
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
      flagInativoCompra: json['flaginativocompra'] ?? '',
    );
  }
  // === ADICIONADO EM 05‑07‑2025: método utilitário para cópia  =================
  /// Cria uma nova instância copiando este objeto e alterando somente
  /// os campos fornecidos.
  VendaPorVendedorProdutoModel copyWith({
    double? qtdProduto,
    double? qtdProdutoVenda,
    double? valTotLiquido,
    double? lucro,
    double? percVendaTotal,
    double? percLucratividade,
  }) {
    return VendaPorVendedorProdutoModel(
      idProduto: idProduto,
      idSubProduto: idSubProduto,
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
  // === FIM ALTERAÇÃO ==========================================================
}
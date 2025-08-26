

class VendaPorVendedorSecaoModel {
  final int idSecao;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  final double percVenda;
  final double percLucro;

  VendaPorVendedorSecaoModel({
    required this.idSecao,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    required this.percVenda,
    required this.percLucro,
  });

  factory VendaPorVendedorSecaoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorVendedorSecaoModel(
      idSecao: json['idsecao'],
      descricao: json['descricao'],
      valTotLiquido: (json['valtotliquido'] as num).toDouble(),
      lucro: (json['lucro'] as num).toDouble(),
      percVenda: (json['percVenda'] as num).toDouble(),
      percLucro: (json['percLucro'] as num).toDouble(),
    );
  }
}
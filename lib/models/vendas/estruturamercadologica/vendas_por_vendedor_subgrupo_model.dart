

class VendaPorVendedorSubgrupoModel {
  final int idSubgrupo;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  final double percVenda;
  final double percLucro;

  VendaPorVendedorSubgrupoModel({
    required this.idSubgrupo,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    required this.percVenda,
    required this.percLucro,
  });

  factory VendaPorVendedorSubgrupoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorVendedorSubgrupoModel(
      idSubgrupo: json['idsubgrupo'],
      descricao: json['descricao'],
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
      percVenda: (json['percVenda'] ?? 0).toDouble(),
      percLucro: (json['percLucro'] ?? 0).toDouble(),
    );
  }
}
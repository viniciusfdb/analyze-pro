

class VendaPorVendedorDivisaoModel {
  final int idDivisao;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  final double percVenda;
  final double percLucro;

  VendaPorVendedorDivisaoModel({
    required this.idDivisao,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    required this.percVenda,
    required this.percLucro,
  });

  factory VendaPorVendedorDivisaoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorVendedorDivisaoModel(
      idDivisao: json['iddivisao'] ?? 0,
      descricao: json['descricao'] ?? '',
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
      percVenda: (json['percVenda'] ?? 0).toDouble(),
      percLucro: (json['percLucro'] ?? 0).toDouble(),
    );
  }
}
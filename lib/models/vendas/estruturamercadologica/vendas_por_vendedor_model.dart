


class VendaPorVendedorModel {
  final int idVendedor;
  final String nome;
  final double totalVenda;
  final double lucro;
  final double percLucratividade;

  VendaPorVendedorModel({
    required this.idVendedor,
    required this.nome,
    required this.totalVenda,
    required this.lucro,
    required this.percLucratividade,
  });

  factory VendaPorVendedorModel.fromJson(Map<String, dynamic> json) {
    return VendaPorVendedorModel(
      idVendedor: json['idvendedor'] ?? 0,
      nome: json['nome'] ?? '',
      totalVenda: (json['totalvenda'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
      percLucratividade: (json['percLucratividade'] ?? 0).toDouble(),
    );
  }

  VendaPorVendedorModel copyWith({
    int? idVendedor,
    String? nome,
    double? totalVenda,
    double? lucro,
    double? percLucratividade,
  }) {
    return VendaPorVendedorModel(
      idVendedor: idVendedor ?? this.idVendedor,
      nome: nome ?? this.nome,
      totalVenda: totalVenda ?? this.totalVenda,
      lucro: lucro ?? this.lucro,
      percLucratividade: percLucratividade ?? this.percLucratividade,
    );
  }
}
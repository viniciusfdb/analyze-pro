class VendaPorDivisaoModel {
  final int idDivisao;
  final String descricao;
  final double valTotLiquido;
  final double lucro;

  // Novos campos calculados
  double? percLucratividade; // lucro / venda
  double? percVendaTotal; // venda / venda total

  VendaPorDivisaoModel({
    required this.idDivisao,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    this.percLucratividade,
    this.percVendaTotal,
  });

  factory VendaPorDivisaoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorDivisaoModel(
      idDivisao: json['iddivisao'] ?? 0,
      descricao: json['descricao'] ?? '',
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'iddivisao': idDivisao,
      'descricao': descricao,
      'valtotliquido': valTotLiquido,
      'lucro': lucro,
      'percLucratividade': percLucratividade,
      'percVendaTotal': percVendaTotal,
    };
  }
  /// Retorna uma cópia deste objeto, alterando apenas os campos informados.
  /// Útil para somar valores quando agregamos mais de uma empresa.
  VendaPorDivisaoModel copyWith({
    int? idDivisao,
    String? descricao,
    double? valTotLiquido,
    double? lucro,
    double? percLucratividade,
    double? percVendaTotal,
  }) {
    return VendaPorDivisaoModel(
      idDivisao: idDivisao ?? this.idDivisao,
      descricao: descricao ?? this.descricao,
      valTotLiquido: valTotLiquido ?? this.valTotLiquido,
      lucro: lucro ?? this.lucro,
      percLucratividade: percLucratividade ?? this.percLucratividade,
      percVendaTotal: percVendaTotal ?? this.percVendaTotal,
    );
  }
}

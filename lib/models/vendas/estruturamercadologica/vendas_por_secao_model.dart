class VendaPorSecaoModel {
  final int idSecao;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  double? percVendaTotal;
  double? percLucratividade;

  VendaPorSecaoModel({
    required this.idSecao,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    this.percVendaTotal,
    this.percLucratividade,
  });

  factory VendaPorSecaoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorSecaoModel(
      idSecao: json['idsecao'] ?? 0,
      descricao: json['descricao'] ?? '',
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idsecao': idSecao,
      'descricao': descricao,
      'valtotliquido': valTotLiquido,
      'lucro': lucro,
    };
  }

  /// Retorna uma cópia deste objeto, alterando apenas os campos informados.
  /// Útil para somar valores quando agregamos mais de uma empresa.
  VendaPorSecaoModel copyWith({
    int? idSecao,
    String? descricao,
    double? valTotLiquido,
    double? lucro,
    double? percVendaTotal,
    double? percLucratividade,
  }) {
    return VendaPorSecaoModel(
      idSecao: idSecao ?? this.idSecao,
      descricao: descricao ?? this.descricao,
      valTotLiquido: valTotLiquido ?? this.valTotLiquido,
      lucro: lucro ?? this.lucro,
      percVendaTotal: percVendaTotal ?? this.percVendaTotal,
      percLucratividade: percLucratividade ?? this.percLucratividade,
    );
  }
}
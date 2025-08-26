class VendaPorSubgrupoModel {
  final int idSubgrupo;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  double? percVendaTotal; // ✅ Novo campo
  double? percLucratividade; // ✅ Novo campo

  VendaPorSubgrupoModel({
    required this.idSubgrupo,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    this.percVendaTotal, // ✅ Novo parâmetro opcional
    this.percLucratividade, // ✅ Novo parâmetro opcional
  });

  factory VendaPorSubgrupoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorSubgrupoModel(
      idSubgrupo: json['idsubgrupo'] ?? 0,
      descricao: json['descricao'] ?? '',
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idsubgrupo': idSubgrupo,
      'descricao': descricao,
      'valtotliquido': valTotLiquido,
      'lucro': lucro,
    };
  }

  /// Retorna uma cópia deste objeto, alterando apenas os campos informados.
  /// Útil para somar valores quando agregamos mais de uma empresa.
  VendaPorSubgrupoModel copyWith({
    int? idSubgrupo,
    String? descricao,
    double? valTotLiquido,
    double? lucro,
    double? percVendaTotal, // ✅ Novo parâmetro opcional
    double? percLucratividade, // ✅ Novo parâmetro opcional
  }) {
    return VendaPorSubgrupoModel(
      idSubgrupo: idSubgrupo ?? this.idSubgrupo,
      descricao: descricao ?? this.descricao,
      valTotLiquido: valTotLiquido ?? this.valTotLiquido,
      lucro: lucro ?? this.lucro,
      percVendaTotal: percVendaTotal ?? this.percVendaTotal, // ✅ Inclusão
      percLucratividade: percLucratividade ?? this.percLucratividade, // ✅ Inclusão
    );
  }
}
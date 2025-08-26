

class VendaPorGrupoModel {
  final int idGrupo;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  double? percVendaTotal;
  double? percLucratividade;

  VendaPorGrupoModel({
    required this.idGrupo,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    this.percVendaTotal,
    this.percLucratividade,
  });

  factory VendaPorGrupoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorGrupoModel(
      idGrupo: json['idgrupo'] ?? 0,
      descricao: json['descricao'] ?? '',
      valTotLiquido: (json['valtotliquido'] ?? 0).toDouble(),
      lucro: (json['lucro'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idgrupo': idGrupo,
      'descricao': descricao,
      'valtotliquido': valTotLiquido,
      'lucro': lucro,
    };
  }

  VendaPorGrupoModel copyWith({
    int? idGrupo,
    String? descricao,
    double? valTotLiquido,
    double? lucro,
    double? percVendaTotal,
    double? percLucratividade,
  }) {
    return VendaPorGrupoModel(
      idGrupo: idGrupo ?? this.idGrupo,
      descricao: descricao ?? this.descricao,
      valTotLiquido: valTotLiquido ?? this.valTotLiquido,
      lucro: lucro ?? this.lucro,
      percVendaTotal: percVendaTotal ?? this.percVendaTotal,
      percLucratividade: percLucratividade ?? this.percLucratividade,
    );
  }
}
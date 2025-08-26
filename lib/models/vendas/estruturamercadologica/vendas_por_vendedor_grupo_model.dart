

class VendaPorVendedorGrupoModel {
  final int idGrupo;
  final String descricao;
  final double valTotLiquido;
  final double lucro;
  final double percVenda;
  final double percLucro;

  VendaPorVendedorGrupoModel({
    required this.idGrupo,
    required this.descricao,
    required this.valTotLiquido,
    required this.lucro,
    required this.percVenda,
    required this.percLucro,
  });

  factory VendaPorVendedorGrupoModel.fromJson(Map<String, dynamic> json) {
    return VendaPorVendedorGrupoModel(
      idGrupo: json['idgrupo'] as int,
      descricao: json['descricao'] as String,
      valTotLiquido: (json['valtotliquido'] as num).toDouble(),
      lucro: (json['lucro'] as num).toDouble(),
      percVenda: (json['percVenda'] as num).toDouble(),
      percLucro: (json['percLucro'] as num).toDouble(),
    );
  }
}
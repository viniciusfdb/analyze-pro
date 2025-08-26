class DiferencaPedidoNotaModel {
  final int idEmpresa;
  final int idCliFor;
  final String nome;
  final int qtdItensDivergentes;
  final double totalDiferencaRs;

  DiferencaPedidoNotaModel({
    required this.idEmpresa,
    required this.idCliFor,
    required this.nome,
    required this.qtdItensDivergentes,
    required this.totalDiferencaRs,
  });

  factory DiferencaPedidoNotaModel.fromJson(Map<String, dynamic> json) {
    return DiferencaPedidoNotaModel(
      idEmpresa: json['idempresa'] as int,
      idCliFor: json['idclifor'] as int,
      nome: json['nome'] as String,
      qtdItensDivergentes: json['qtdItensDivergentes'] as int,
      totalDiferencaRs: (json['totalDiferencaRs'] as num).toDouble(),
    );
  }
  DiferencaPedidoNotaModel copyWith({
    int? idEmpresa,
    int? idCliFor,
    String? nome,
    int? qtdItensDivergentes,
    double? totalDiferencaRs,
  }) {
    return DiferencaPedidoNotaModel(
      idEmpresa: idEmpresa ?? this.idEmpresa,
      idCliFor: idCliFor ?? this.idCliFor,
      nome: nome ?? this.nome,
      qtdItensDivergentes: qtdItensDivergentes ?? this.qtdItensDivergentes,
      totalDiferencaRs: totalDiferencaRs ?? this.totalDiferencaRs,
    );
  }
}
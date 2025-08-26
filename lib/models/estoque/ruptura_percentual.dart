class RupturaPercentual {
  final int idEmpresa;
  final int idDivisao;
  final String descrDivisao;
  final int idSecao;
  final String descrSecao;
  final int skusAtivos;
  final int skusRuptura;
  final double percRuptura;

  RupturaPercentual({
    required this.idEmpresa,
    required this.idDivisao,
    required this.descrDivisao,
    required this.idSecao,
    required this.descrSecao,
    required this.skusAtivos,
    required this.skusRuptura,
    required this.percRuptura,
  });

  factory RupturaPercentual.fromJson(Map<String, dynamic> json) {
    return RupturaPercentual(
      idEmpresa: json['idempresa'] as int,
      idDivisao: (json['iddivisao'] as int?) ?? 0,
      descrDivisao: (json['descrdivisao'] as String?)?.trim() ?? '',
      idSecao: json['idsecao'] as int,
      descrSecao: (json['descrsecao'] as String?)?.trim() ?? '',
      skusAtivos: (json['skusAtivos'] as int?) ?? 0,
      skusRuptura: (json['skusRuptura'] as int?) ?? 0,
      percRuptura: (json['percRuptura'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'idempresa': idEmpresa,
    'iddivisao': idDivisao,
    'descrdivisao': descrDivisao,
    'idsecao': idSecao,
    'descrsecao': descrSecao,
    'skusAtivos': skusAtivos,
    'skusRuptura': skusRuptura,
    'percRuptura': percRuptura,
  };
}
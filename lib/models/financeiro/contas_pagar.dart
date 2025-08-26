class ContasPagar {
  final int idEmpresa;
  final double totalAPagar;
  final double totalPago;
  final double saldoAPagar;
  final double valorLiquidoPagar;
  final double percentualPago;
  final double totalJuroMora;
  final double totalJuroCobrado;
  final double totalJuroIsentado;
  final double totalJuroPostergado;
  final double totalDescontosConcedidos;
  final int qtdeTitulosAtrasados;
  final int mediaDiasAtraso;

  ContasPagar({
    required this.idEmpresa,
    required this.totalAPagar,
    required this.totalPago,
    required this.saldoAPagar,
    required this.valorLiquidoPagar,
    required this.percentualPago,
    required this.totalJuroMora,
    required this.totalJuroCobrado,
    required this.totalJuroIsentado,
    required this.totalJuroPostergado,
    required this.totalDescontosConcedidos,
    required this.qtdeTitulosAtrasados,
    required this.mediaDiasAtraso,
  });

  factory ContasPagar.fromJson(Map<String, dynamic> json) => ContasPagar(
    idEmpresa: json['idempresa'] ?? 0,
    totalAPagar: (json['totalAPagar'] as num?)?.toDouble() ?? 0.0,
    totalPago: (json['totalPago'] as num?)?.toDouble() ?? 0.0,
    saldoAPagar: (json['saldoAPagar'] as num?)?.toDouble() ?? 0.0,
    valorLiquidoPagar: (json['valorLiquidoPagar'] as num?)?.toDouble() ?? 0.0,
    percentualPago: (json['percentualPago'] as num?)?.toDouble() ?? 0.0,
    totalJuroMora: (json['totalJuroMora'] as num?)?.toDouble() ?? 0.0,
    totalJuroCobrado: (json['totalJuroCobrado'] as num?)?.toDouble() ?? 0.0,
    totalJuroIsentado: (json['totalJuroIsentado'] as num?)?.toDouble() ?? 0.0,
    totalJuroPostergado: (json['totalJuroPostergado'] as num?)?.toDouble() ?? 0.0,
    totalDescontosConcedidos: (json['totalDescontosConcedidos'] as num?)?.toDouble() ?? 0.0,
    qtdeTitulosAtrasados: json['qtdeTitulosAtrasados'] ?? 0,
    mediaDiasAtraso: json['mediaDiasAtraso'] ?? 0,
  );
}
class ContasReceber {
  final int idEmpresa;
  final double totalAReceber;
  final double totalPago;
  final double saldoAReceber;
  final double valorLiquidoReceber;
  final double percentualRecebido;
  final double totalJuroMora;
  final double totalJuroCobrado;
  final double totalJuroIsentado;
  final double totalJuroPostergado;
  final double totalDescontosConcedidos;
  final int qtdeTitulosAtrasados;
  final int mediaDiasAtraso;

  ContasReceber({
    required this.idEmpresa,
    required this.totalAReceber,
    required this.totalPago,
    required this.saldoAReceber,
    required this.valorLiquidoReceber,
    required this.percentualRecebido,
    required this.totalJuroMora,
    required this.totalJuroCobrado,
    required this.totalJuroIsentado,
    required this.totalJuroPostergado,
    required this.totalDescontosConcedidos,
    required this.qtdeTitulosAtrasados,
    required this.mediaDiasAtraso,
  });

  factory ContasReceber.fromJson(Map<String, dynamic> json) => ContasReceber(
    idEmpresa: json['idempresa'] ?? 0,
    totalAReceber: (json['totalAReceber'] as num?)?.toDouble() ?? 0.0,
    totalPago: (json['totalPago'] as num?)?.toDouble() ?? 0.0,
    saldoAReceber: (json['saldoAReceber'] as num?)?.toDouble() ?? 0.0,
    valorLiquidoReceber: (json['valorLiquidoReceber'] as num?)?.toDouble() ?? 0.0,
    percentualRecebido: (json['percentualRecebido'] as num?)?.toDouble() ?? 0.0,
    totalJuroMora: (json['totalJuroMora'] as num?)?.toDouble() ?? 0.0,
    totalJuroCobrado: (json['totalJuroCobrado'] as num?)?.toDouble() ?? 0.0,
    totalJuroIsentado: (json['totalJuroIsentado'] as num?)?.toDouble() ?? 0.0,
    totalJuroPostergado: (json['totalJuroPostergado'] as num?)?.toDouble() ?? 0.0,
    totalDescontosConcedidos: (json['totalDescontosConcedidos'] as num?)?.toDouble() ?? 0.0,
    qtdeTitulosAtrasados: json['qtdeTitulosAtrasados'] ?? 0,
    mediaDiasAtraso: json['mediaDiasAtraso'] ?? 0,
  );
}

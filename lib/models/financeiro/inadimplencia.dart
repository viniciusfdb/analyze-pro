class Inadimplencia {
  final int idEmpresa;
  final int mes;
  final int ano;
  final double valTitulos;
  final double valDescConcedido;
  final double valPagoEmDia;
  final double valPagoInadimp;
  final double valInadimpAtual;
  final double valInadimpMes;
  final double valPendente;
  final double valPerda;

  Inadimplencia({
    required this.idEmpresa,
    required this.mes,
    required this.ano,
    required this.valTitulos,
    required this.valDescConcedido,
    required this.valPagoEmDia,
    required this.valPagoInadimp,
    required this.valInadimpAtual,
    required this.valInadimpMes,
    required this.valPendente,
    required this.valPerda,
  });

  factory Inadimplencia.fromJson(Map<String, dynamic> json) {
    return Inadimplencia(
      idEmpresa: json['idempresa'] ?? 0,
      mes: json['mes'] ?? 0,
      ano: json['ano'] ?? 0,
      valTitulos: (json['valtitulos'] as num?)?.toDouble() ?? 0.0,
      valDescConcedido: (json['valdescconcedido'] as num?)?.toDouble() ?? 0.0,
      valPagoEmDia: (json['valpagoemdia'] as num?)?.toDouble() ?? 0.0,
      valPagoInadimp: (json['valpagoinadimp'] as num?)?.toDouble() ?? 0.0,
      valInadimpAtual: (json['valinadimpatual'] as num?)?.toDouble() ?? 0.0,
      valInadimpMes: (json['valinadimpmes'] as num?)?.toDouble() ?? 0.0,
      valPendente: (json['valpendente'] as num?)?.toDouble() ?? 0.0,
      valPerda: (json['valperda'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
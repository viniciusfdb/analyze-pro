class TopDevedor {
  final int idempresa;
  final int idclifor;
  final String nome;
  final double valordevido;
  final int qtdtitulos;
  final double totaltitulos;
  final double totalpago;
  final double juros;
  final double saldocomjuros;

  TopDevedor({
    required this.idempresa,
    required this.idclifor,
    required this.nome,
    required this.valordevido,
    required this.qtdtitulos,
    required this.totaltitulos,
    required this.totalpago,
    required this.juros,
    required this.saldocomjuros,
  });

  factory TopDevedor.fromJson(Map<String, dynamic> json) {
    return TopDevedor(
      idempresa: json['idempresa'],
      idclifor: json['idclifor'],
      nome: json['nome'],
      valordevido: (json['valorDevido'] as num).toDouble(),
      qtdtitulos: (json['qtdTitulos'] as num).toInt(),
      totaltitulos: (json['totalTitulos'] as num).toDouble(),
      totalpago: (json['totalPago'] as num).toDouble(),
      juros: (json['juros'] as num).toDouble(),
      saldocomjuros: (json['saldoComJuros'] as num).toDouble(),
    );
  }
}
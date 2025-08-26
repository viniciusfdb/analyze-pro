class InventarioEstoque {
  final DateTime dtMovimento;
  final int idEmpresa;
  final double qtdAtualEstoque;
  final double custoMedio;
  final double valorTotal;

  InventarioEstoque({
    required this.dtMovimento,
    required this.idEmpresa,
    required this.qtdAtualEstoque,
    required this.custoMedio,
    required this.valorTotal,
  });

  factory InventarioEstoque.fromJson(Map<String, dynamic> json) {
    return InventarioEstoque(
      dtMovimento: DateTime.parse(json['dtmovimento']),
      idEmpresa: json['idempresa'],
      qtdAtualEstoque: (json['qtdatualestoque'] ?? 0).toDouble(),
      custoMedio: (json['custoMedio'] ?? 0).toDouble(),
      valorTotal: (json['valorTotal'] ?? 0).toDouble(),
    );
  }
}
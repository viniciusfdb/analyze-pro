class FaturamentoComLucro {
  final int idEmpresa;
  final DateTime dtMovimento;
  final double totalVenda;
  final double lucro;
  final double totalVendaBruta;
  final double lucroBruto;
  final double devolucoes;
  final int nroVendas;
  final double ticketMedio;

  FaturamentoComLucro({
    required this.idEmpresa,
    required this.dtMovimento,
    required this.totalVenda,
    required this.lucro,
    required this.totalVendaBruta,
    required this.lucroBruto,
    required this.devolucoes,
    required this.nroVendas,
    required this.ticketMedio,
  });

  factory FaturamentoComLucro.fromJson(Map<String, dynamic> json) {
    return FaturamentoComLucro(
      idEmpresa: json['idempresa'] ?? 0,
      dtMovimento: json['dtmovimento'] != null
          ? DateTime.parse(json['dtmovimento'])
          : DateTime.now(),
      totalVenda: (json['totalvenda'] as num?)?.toDouble() ?? 0.0,
      lucro: (json['lucro'] as num?)?.toDouble() ?? 0.0,
      totalVendaBruta: (json['totalvendabruta'] as num?)?.toDouble() ?? 0.0,
      lucroBruto: (json['lucrobruto'] as num?)?.toDouble() ?? 0.0,
      devolucoes: (json['devolucoes'] as num?)?.toDouble() ?? 0.0,
      nroVendas: json['nrovendas'] ?? 0,
      ticketMedio: (json['ticketMedio'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory FaturamentoComLucro.fromMap(Map<String, dynamic> map) {
    return FaturamentoComLucro(
      idEmpresa: map['idempresa'] ?? 0,
      dtMovimento: DateTime.parse(map['dtmovimento']),
      totalVenda: (map['totalvenda'] ?? 0).toDouble(),
      lucro: (map['lucro'] ?? 0).toDouble(),
      totalVendaBruta: (map['totalvendabruta'] ?? 0).toDouble(),
      lucroBruto: (map['lucrobruto'] ?? 0).toDouble(),
      devolucoes: (map['devolucoes'] ?? 0).toDouble(),
      nroVendas: map['nrovendas'] ?? 0,
      ticketMedio: (map['ticketMedio'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempresa': idEmpresa,
      'dtmovimento': dtMovimento.toIso8601String(),
      'totalvenda': totalVenda,
      'lucro': lucro,
      'totalvendabruta': totalVendaBruta,
      'lucrobruto': lucroBruto,
      'devolucoes': devolucoes,
      'nrovendas': nroVendas,
      'ticketMedio': ticketMedio,
    };
  }
}
class DocumentosFiscaisSaidaResumo {
  final int qtd;
  final double somaValorLiqDocSaida;

  DocumentosFiscaisSaidaResumo({
    required this.qtd,
    required this.somaValorLiqDocSaida,
  });

  factory DocumentosFiscaisSaidaResumo.fromJson(Map<String, dynamic> json) {
    final dynamic qtdRaw = json['qtd'];
    final dynamic somaRaw = json['somaValorLiqDocSaida'];

    return DocumentosFiscaisSaidaResumo(
      qtd: (qtdRaw is num) ? qtdRaw.toInt() : int.tryParse(qtdRaw?.toString() ?? '0') ?? 0,
      somaValorLiqDocSaida: (somaRaw is num) ? somaRaw.toDouble() : double.tryParse(somaRaw?.toString() ?? '0') ?? 0.0,
    );
  }
}
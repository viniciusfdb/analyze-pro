import 'package:intl/intl.dart';

class TaxaAdministradora {
  final int idAdministradora;
  final String descrAdministradora;
  final int idBandeira;
  final String descrInstituicao;
  final int idEmpresa;
  final double taxaCadastro;
  final double taxaAdm;
  final int idNsuHost;
  final int parcelaAdm;
  final String dtMovimento;
  final double valTitulo;
  final double valLiquidoEsperado;
  final double valLiquidoPago;
  final double dif;

  TaxaAdministradora({
    required this.idAdministradora,
    required this.descrAdministradora,
    required this.idBandeira,
    required this.descrInstituicao,
    required this.idEmpresa,
    required this.taxaCadastro,
    required this.taxaAdm,
    required this.idNsuHost,
    required this.parcelaAdm,
    required this.dtMovimento,
    required this.valTitulo,
    required this.valLiquidoEsperado,
    required this.valLiquidoPago,
    required this.dif,
  });

  factory TaxaAdministradora.fromJson(Map<String, dynamic> json) {
    return TaxaAdministradora(
      idAdministradora: (json['idadministradora'] as num?)?.toInt() ?? 0,
      descrAdministradora: json['descradministradora'] ?? '',
      idBandeira: (json['idbandeira'] as num?)?.toInt() ?? 0,
      descrInstituicao: json['descrinstituicao'] ?? '',
      idEmpresa: (json['idempresa'] as num?)?.toInt() ?? 0,
      taxaCadastro: (json['taxa_cadastro'] as num?)?.toDouble() ?? 0.0,
      taxaAdm: (json['taxa_adm'] as num?)?.toDouble() ?? 0.0,
      idNsuHost: (json['idnsuhost'] as num?)?.toInt() ?? 0,
      parcelaAdm: (json['parcela_adm'] as num?)?.toInt() ?? 0,
      dtMovimento: _formatarData(json['dtmovimento']), // ✅ Aqui chamamos a função de conversão
      valTitulo: (json['valtitulo'] as num?)?.toDouble() ?? 0.0,
      valLiquidoEsperado: (json['valliquidoesperado'] as num?)?.toDouble() ?? 0.0,
      valLiquidoPago: (json['valliquidopago'] as num?)?.toDouble() ?? 0.0,
      dif: (json['dif'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// **📌 Função para converter a data do formato americano (YYYY-MM-DD) para brasileiro (DD/MM/YYYY)**
  static String _formatarData(String? data) {
    if (data == null || data.isEmpty) return '';
    try {
      DateTime date = DateTime.parse(data);
      return DateFormat('dd/MM/yyyy').format(date); // ✅ Converte para o formato brasileiro
    } catch (e) {
      return data; // Se houver erro, mantém a data original
    }
  }

}

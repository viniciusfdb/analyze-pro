import 'package:intl/intl.dart';

class FechamentoCaixa {
  final String caixa;
  final String idusuario;
  final String usuario;
  final DateTime dtmovimento;
  final String idempresa;
  final String abertura;
  final String saldo;
  final double valResultado;
  final String flagconferido;
  final double sobra;
  final double falta;

  FechamentoCaixa({
    required this.caixa,
    required this.idusuario,
    required this.usuario,
    required this.dtmovimento,
    required this.idempresa,
    required this.abertura,
    required this.saldo,
    required this.valResultado,
    required this.flagconferido,
    required this.sobra, // 🔹 Novo campo
    required this.falta, // 🔹 Novo campo
  });

  /// 🔹 Converte JSON em um objeto FechamentoCaixa
  factory FechamentoCaixa.fromJson(Map<String, dynamic> json) {
    return FechamentoCaixa(
      caixa: json['idcaixa']?.toString() ?? '',
      idusuario: json['idusuario']?.toString() ?? '',
      usuario: json['usuario']?.toString() ?? '',
      dtmovimento: _parseDateTime(json['dtmovimento']),
      idempresa: json['idempresa']?.toString() ?? '',
      abertura: json['abertura']?.toString() ?? '',
      saldo: json['saldo']?.toString() ?? '',
      valResultado: double.tryParse(json['valresultado']?.toString() ?? '0') ?? 0.0,
      flagconferido: json['flagconferido']?.toString().trim() ?? '',
      sobra: double.tryParse(json['sobra']?.toString() ?? '0') ?? 0.0, // 🔹 Converte sobra corretamente
      falta: double.tryParse(json['falta']?.toString() ?? '0') ?? 0.0, // 🔹 Converte falta corretamente
    );
  }

  /// 🔹 Método auxiliar para converter dtmovimento corretamente em DateTime
  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value; // Já é um DateTime, então retorna diretamente.
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        print("Erro ao converter dtmovimento: $value - Erro: $e");
      }
    }
    return DateTime(2000, 1, 1); // Valor padrão caso falhe a conversão.
  }

  /// 🔹 Método auxiliar para obter dtmovimento formatado como String
  String get dtmovimentoFormatado => DateFormat('yyyy-MM-dd').format(dtmovimento);
}

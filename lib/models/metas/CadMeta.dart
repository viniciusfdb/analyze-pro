class CadMeta {
  final int idempresa;
  final int idmeta;
  final String descrmeta;
  final DateTime dtinicial;
  final DateTime dtfinal;
  final int? numsequencia;   // agora nullable
  final int? idvendedor;     // agora nullable
  final double metavlrvenda;

  CadMeta({
    required this.idempresa,
    required this.idmeta,
    required this.descrmeta,
    required this.dtinicial,
    required this.dtfinal,
    this.numsequencia,
    this.idvendedor,
    required this.metavlrvenda,
  });

  factory CadMeta.fromJson(Map<String, dynamic> json) {
    return CadMeta(
      idempresa: json['idempresa'] as int,
      idmeta:    json['idmeta']    as int,
      descrmeta: json['descrmeta'] as String,
      dtinicial: DateTime.parse(json['dtinicial'] as String),
      dtfinal:   DateTime.parse(json['dtfinal']   as String),
      numsequencia: (json['numsequencia'] as int?) ?? 0,
      idvendedor:   (json['idvendedor']   as int?) ?? 0,
      metavlrvenda: (json['metavlrvenda'] as num).toDouble(),
    );
  }

  int get valorMeta => metavlrvenda.toInt();
}
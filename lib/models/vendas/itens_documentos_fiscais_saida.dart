class ItensDocumentosFiscaisSaida {
  final int idempresa;
  final int idplanilha;
  final int idvendedor;
  final int idproduto;
  final int idsubproduto;
  final int numsequencia;
  final double valdescontoproduto;
  final double valacrescimoproduto;
  final double valimpostos;
  final double valfrete;
  final double qtdproduto;
  final double valunitbruto;
  final double valtotliquido;
  final String dtmovimento;
  final String descrproduto;
  final int cfop;
  final int idoperacao;
  final String descroperacao;

  ItensDocumentosFiscaisSaida({
    required this.idempresa,
    required this.idplanilha,
    required this.idvendedor,
    required this.idproduto,
    required this.idsubproduto,
    required this.numsequencia,
    required this.valdescontoproduto,
    required this.valacrescimoproduto,
    required this.valimpostos,
    required this.valfrete,
    required this.qtdproduto,
    required this.valunitbruto,
    required this.valtotliquido,
    required this.dtmovimento,
    required this.descrproduto,
    required this.cfop,
    required this.idoperacao,
    required this.descroperacao,
  });

  factory ItensDocumentosFiscaisSaida.fromJson(Map<String, dynamic> json) {
    return ItensDocumentosFiscaisSaida(
      idempresa: json['idempresa'] ?? 0,
      idplanilha: json['idplanilha'] ?? 0,
      idvendedor: json['idvendedor'] ?? 0,
      idproduto: json['idproduto'] ?? 0,
      idsubproduto: json['idsubproduto'] ?? 0,
      numsequencia: json['numsequencia'] ?? 0,
      valdescontoproduto: (json['valdescontoproduto'] as num?)?.toDouble() ?? 0.0,
      valacrescimoproduto: (json['valacrescimoproduto'] as num?)?.toDouble() ?? 0.0,
      valimpostos: (json['valimpostos'] as num?)?.toDouble() ?? 0.0,
      valfrete: (json['valfrete'] as num?)?.toDouble() ?? 0.0,
      qtdproduto: (json['qtdproduto'] as num?)?.toDouble() ?? 0.0,
      valunitbruto: (json['valunitbruto'] as num?)?.toDouble() ?? 0.0,
      valtotliquido: (json['valtotliquido'] as num?)?.toDouble() ?? 0.0,
      dtmovimento: json['dtmovimento'] ?? '',
      descrproduto: json['descrproduto'] ?? '',
      cfop: json['cfop'] ?? 0,
      idoperacao: json['idoperacao'] ?? 0,
      descroperacao: json['descroperacao'] ?? '',
    );
  }

  factory ItensDocumentosFiscaisSaida.fromMap(Map<String, dynamic> map) {
    return ItensDocumentosFiscaisSaida(
      idempresa: map['idempresa'] ?? 0,
      idplanilha: map['idplanilha'] ?? 0,
      idvendedor: map['idvendedor'] ?? 0,
      idproduto: map['idproduto'] ?? 0,
      idsubproduto: map['idsubproduto'] ?? 0,
      numsequencia: map['numsequencia'] ?? 0,
      valdescontoproduto: (map['valdescontoproduto'] ?? 0).toDouble(),
      valacrescimoproduto: (map['valacrescimoproduto'] ?? 0).toDouble(),
      valimpostos: (map['valimpostos'] ?? 0).toDouble(),
      valfrete: (map['valfrete'] ?? 0).toDouble(),
      qtdproduto: (map['qtdproduto'] ?? 0).toDouble(),
      valunitbruto: (map['valunitbruto'] ?? 0).toDouble(),
      valtotliquido: (map['valtotliquido'] ?? 0).toDouble(),
      dtmovimento: map['dtmovimento'] ?? '',
      descrproduto: map['descrproduto'] ?? '',
      cfop: map['cfop'] ?? 0,
      idoperacao: map['idoperacao'] ?? 0,
      descroperacao: map['descroperacao'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempresa': idempresa,
      'idplanilha': idplanilha,
      'idvendedor': idvendedor,
      'idproduto': idproduto,
      'idsubproduto': idsubproduto,
      'numsequencia': numsequencia,
      'valdescontoproduto': valdescontoproduto,
      'valacrescimoproduto': valacrescimoproduto,
      'valimpostos': valimpostos,
      'valfrete': valfrete,
      'qtdproduto': qtdproduto,
      'valunitbruto': valunitbruto,
      'valtotliquido': valtotliquido,
      'dtmovimento': dtmovimento,
      'descrproduto': descrproduto,
      'cfop': cfop,
      'idoperacao': idoperacao,
      'descroperacao': descroperacao,
    };
  }
  ItensDocumentosFiscaisSaida copyWith({
    int? idempresa,
    int? idplanilha,
    int? idvendedor,
    int? idproduto,
    int? idsubproduto,
    int? numsequencia,
    double? valdescontoproduto,
    double? valacrescimoproduto,
    double? valimpostos,
    double? valfrete,
    double? qtdproduto,
    double? valunitbruto,
    double? valtotliquido,
    String? dtmovimento,
    String? descrproduto,
    int? cfop,
    int? idoperacao,
    String? descroperacao,
  }) {
    return ItensDocumentosFiscaisSaida(
      idempresa: idempresa ?? this.idempresa,
      idplanilha: idplanilha ?? this.idplanilha,
      idvendedor: idvendedor ?? this.idvendedor,
      idproduto: idproduto ?? this.idproduto,
      idsubproduto: idsubproduto ?? this.idsubproduto,
      numsequencia: numsequencia ?? this.numsequencia,
      valdescontoproduto: valdescontoproduto ?? this.valdescontoproduto,
      valacrescimoproduto: valacrescimoproduto ?? this.valacrescimoproduto,
      valimpostos: valimpostos ?? this.valimpostos,
      valfrete: valfrete ?? this.valfrete,
      qtdproduto: qtdproduto ?? this.qtdproduto,
      valunitbruto: valunitbruto ?? this.valunitbruto,
      valtotliquido: valtotliquido ?? this.valtotliquido,
      dtmovimento: dtmovimento ?? this.dtmovimento,
      descrproduto: descrproduto ?? this.descrproduto,
      cfop: cfop ?? this.cfop,
      idoperacao: idoperacao ?? this.idoperacao,
      descroperacao: descroperacao ?? this.descroperacao,
    );
  }
}
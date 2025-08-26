class DiferencaPedidoNotaDetalhesModel {
  final int idEmpresa;
  final String dtMovimento;        // AAAA‑MM‑DD no retorno da API
  final int idCliFor;
  final String nome;
  final int numNota;
  final int idPedido;
  final double qtdNota;
  final double qtdSolicitada;
  final int idSubproduto;
  final String descrResProduto;
  final double pedTotal;
  final double pedBruto;
  final double notaTotal;
  final double valTotBruto;
  final double dif;

  const DiferencaPedidoNotaDetalhesModel({
    required this.idEmpresa,
    required this.dtMovimento,
    required this.idCliFor,
    required this.nome,
    required this.numNota,
    required this.idPedido,
    required this.qtdNota,
    required this.qtdSolicitada,
    required this.idSubproduto,
    required this.descrResProduto,
    required this.pedTotal,
    required this.pedBruto,
    required this.notaTotal,
    required this.valTotBruto,
    required this.dif,
  });

  factory DiferencaPedidoNotaDetalhesModel.fromJson(Map<String, dynamic> json) {
    return DiferencaPedidoNotaDetalhesModel(
      idEmpresa: json['idempresa'] as int,
      dtMovimento: json['dtmovimento'] as String,
      idCliFor: json['idclifor'] as int,
      nome: json['nome'] as String,
      numNota: json['numnota'] as int,
      idPedido: json['idpedido'] as int,
      qtdNota: (json['qtdNota'] as num).toDouble(),
      qtdSolicitada: (json['qtdsolicitada'] as num).toDouble(),
      idSubproduto: json['idsubproduto'] as int,
      descrResProduto: json['descrresproduto'] as String,
      pedTotal: (json['pedTotal'] as num).toDouble(),
      pedBruto: (json['pedBruto'] as num).toDouble(),
      notaTotal: (json['notaTotal'] as num).toDouble(),
      valTotBruto: (json['valtotbruto'] as num).toDouble(),
      dif: (json['dif'] as num).toDouble(),
    );
  }

  DiferencaPedidoNotaDetalhesModel copyWith({
    int? idEmpresa,
    String? dtMovimento,
    int? idCliFor,
    String? nome,
    int? numNota,
    int? idPedido,
    double? qtdNota,
    double? qtdSolicitada,
    int? idSubproduto,
    String? descrResProduto,
    double? pedTotal,
    double? pedBruto,
    double? notaTotal,
    double? valTotBruto,
    double? dif,
  }) {
    return DiferencaPedidoNotaDetalhesModel(
      idEmpresa: idEmpresa ?? this.idEmpresa,
      dtMovimento: dtMovimento ?? this.dtMovimento,
      idCliFor: idCliFor ?? this.idCliFor,
      nome: nome ?? this.nome,
      numNota: numNota ?? this.numNota,
      idPedido: idPedido ?? this.idPedido,
      qtdNota: qtdNota ?? this.qtdNota,
      qtdSolicitada: qtdSolicitada ?? this.qtdSolicitada,
      idSubproduto: idSubproduto ?? this.idSubproduto,
      descrResProduto: descrResProduto ?? this.descrResProduto,
      pedTotal: pedTotal ?? this.pedTotal,
      pedBruto: pedBruto ?? this.pedBruto,
      notaTotal: notaTotal ?? this.notaTotal,
      valTotBruto: valTotBruto ?? this.valTotBruto,
      dif: dif ?? this.dif,
    );
  }
}


class ContasReceberVencimentoDetalhadoModel {
  final int idClifor;
  final String nome;
  final String cnpjCpf;
  final int idTitulo;
  final String obstitulo;
  final String descrRecebimento;
  final double valTitulo;
  final double valLiquidoTitulo;
  final DateTime dtVencimento;

  ContasReceberVencimentoDetalhadoModel({
    required this.idClifor,
    required this.nome,
    required this.cnpjCpf,
    required this.idTitulo,
    required this.obstitulo,
    required this.descrRecebimento,
    required this.valTitulo,
    required this.valLiquidoTitulo,
    required this.dtVencimento,
  });

  factory ContasReceberVencimentoDetalhadoModel.fromJson(Map<String, dynamic> json) {
    return ContasReceberVencimentoDetalhadoModel(
      idClifor: json['idclifor'],
      nome: json['nome'] ?? '',
      cnpjCpf: json['cnpjcpf'] ?? '',
      idTitulo: json['idtitulo'],
      obstitulo: json['obstitulo'] ?? '',
      descrRecebimento: json['descrrecebimento'] ?? '',
      valTitulo: (json['valtitulo'] as num).toDouble(),
      valLiquidoTitulo: (json['valliquidotitulo'] as num).toDouble(),
      dtVencimento: DateTime.parse(json['dtvencimento']),
    );
  }
}
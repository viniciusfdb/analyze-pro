class EmpresaColaborador {
  final int idempresa;
  final int ano;
  final int mes;
  final int numcolaboradores;

  EmpresaColaborador({
    required this.idempresa,
    required this.ano,
    required this.mes,
    required this.numcolaboradores,
  });

  factory EmpresaColaborador.fromJson(Map<String, dynamic> json) {
    return EmpresaColaborador(
      idempresa: json['idempresa'],
      ano: json['ano'],
      mes: json['mes'],
      numcolaboradores: json['numcolaboradores'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idempresa': idempresa,
      'ano': ano,
      'mes': mes,
      'numcolaboradores': numcolaboradores,
    };
  }
}
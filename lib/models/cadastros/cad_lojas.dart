class Empresa {
  final int id;
  final String nome;

  Empresa({required this.id, required this.nome});

  factory Empresa.fromMap(Map<String, dynamic> map) {
    return Empresa(
      id: map['idempresa'] ?? 0,
      nome: map['nomefantasia'] ?? 'Empresa sem nome',
    );
  }

  get fantasia => null;

  get idempresa => null;

  get nomeFantasia => null;

  @override
  String toString() => '$id - $nome';
}
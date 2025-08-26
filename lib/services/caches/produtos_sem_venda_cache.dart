/// 28‑06‑2025 – Cache e sessão compartilhada da tela “Produtos sem Venda”.
///
/// Mantém:
/// * Requisição única (globalFetching/globalFuture)
/// * Lista de empresas (cachedEmpresas) com TTL de 30 min
/// * Resultado da busca (cachedLista) com TTL de 30 min
/// * Últimos filtros usados (empresa, diasSemVenda)
///
/// Use:  `final _cache = ProdutosSemVendaCache.instance;`

import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import '../../models/vendas/produto_sem_venda.dart';

class ProdutosSemVendaCache {
  ProdutosSemVendaCache._();
  static final ProdutosSemVendaCache instance = ProdutosSemVendaCache._();

  // === Controle de requisição única ===
  bool globalFetching = false;
  Future<void>? globalFuture;

  // === Cache da lista de empresas ===
  List<Empresa>? cachedEmpresas;
  DateTime? _empresasTimestamp;
  final int _empresasTtlMin = 30;

  bool get empresasValidas =>
      cachedEmpresas != null &&
      _empresasTimestamp != null &&
      DateTime.now().difference(_empresasTimestamp!).inMinutes < _empresasTtlMin;

  void setEmpresas(List<Empresa> lista) {
    cachedEmpresas = List<Empresa>.from(lista);
    _empresasTimestamp = DateTime.now();
  }

  // === Cache do resultado (produtos sem venda) ===
  List<ProdutoSemVenda>? cachedLista;
  DateTime? _listaTimestamp;
  List<int>? listaEmpresas;
  int? listaDias;
  String? listaFiltroSaldo;
  final int _listaTtlMin = 30;

  // Getters for cache metadata
  DateTime? get empresasTimestamp => _empresasTimestamp;
  int get empresasTtlMin => _empresasTtlMin;
  DateTime? get listaTimestamp => _listaTimestamp;
  int get listaTtlMin => _listaTtlMin;

  bool resultadoValido(
    List<int> empresas,
    int dias,
    String filtroSaldo,
  ) =>
      cachedLista != null &&
      _listaTimestamp != null &&
      DateTime.now().difference(_listaTimestamp!).inMinutes < _listaTtlMin &&
      listaEmpresas != null &&
      _listasIguais(empresas, listaEmpresas!) &&
      dias == listaDias &&
      listaFiltroSaldo == filtroSaldo;

  bool _listasIguais(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final setA = Set.of(a);
    final setB = Set.of(b);
    return setA.containsAll(setB) && setB.containsAll(setA);
  }

  void setResultado({
    required List<ProdutoSemVenda> lista,
    required List<int> empresas,
    required int dias,
    required String filtroSaldo,
  }) {
    cachedLista = List<ProdutoSemVenda>.from(lista);
    _listaTimestamp = DateTime.now();
    listaEmpresas = List<int>.from(empresas);
    listaDias = dias;
    listaFiltroSaldo = filtroSaldo;
  }

  // === Memória de filtros ===
  Empresa? lastEmpresaSelecionada;
  int? lastDiasSemVenda;
}

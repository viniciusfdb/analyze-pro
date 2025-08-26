import 'package:flutter/material.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/models/vendas/estruturamercadologica/vendas_por_produto_model.dart';

class TopProdutosVendidosCache {
  static final TopProdutosVendidosCache instance = TopProdutosVendidosCache._internal();

  TopProdutosVendidosCache._internal();

  List<VendaPorProdutoModel>? _itens;
  List<Empresa>? _empresasSelecionadas;
  DateTimeRange? _intervaloSelecionado;
  DateTime? _ultimaAtualizacao;
  double? _tempoExecucao;
  double? _tempoMedioEstimado;

  void salvar({
    required List<VendaPorProdutoModel> itens,
    required List<Empresa> empresas,
    required DateTimeRange intervalo,
    required double tempoExecucaoSegundos,
    required double tempoMedioEstimadoSegundos,
  }) {
    _itens = itens;
    _empresasSelecionadas = empresas;
    _intervaloSelecionado = intervalo;
    _ultimaAtualizacao = DateTime.now();
    _tempoExecucao = tempoExecucaoSegundos;
    _tempoMedioEstimado = tempoMedioEstimadoSegundos;
  }

  bool get cacheValido {
    if (_ultimaAtualizacao == null) return false;
    return DateTime.now().difference(_ultimaAtualizacao!) <= const Duration(minutes: 30);
  }

  List<VendaPorProdutoModel>? get itens => _itens;
  List<VendaPorProdutoModel>? get produtos => _itens;
  List<Empresa>? get empresasSelecionadas => _empresasSelecionadas;
  DateTimeRange? get intervaloSelecionado => _intervaloSelecionado;
  double? get tempoExecucao => _tempoExecucao;
  double? get tempoMedioEstimado => _tempoMedioEstimado;

  void limpar() {
    _itens = null;
    _empresasSelecionadas = null;
    _intervaloSelecionado = null;
    _ultimaAtualizacao = null;
  }

  bool contemFiltroAtivo({
    required List<Empresa> empresasSelecionadas,
    required DateTimeRange intervaloSelecionado,
  }) {
    if (!cacheValido) return false;
    if (_empresasSelecionadas == null || _intervaloSelecionado == null) return false;

    final mesmasEmpresas = _empresasSelecionadas!.length == empresasSelecionadas.length &&
        _empresasSelecionadas!.every((e) => empresasSelecionadas.any((f) => f.idempresa == e.idempresa));

    final mesmoIntervalo = _intervaloSelecionado!.start == intervaloSelecionado.start &&
        _intervaloSelecionado!.end == intervaloSelecionado.end;

    return mesmasEmpresas && mesmoIntervalo;
  }
}

import 'package:flutter/material.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import '../../models/vendas/faturamento_com_lucro_model.dart';

class VendasPageCache {
  static final VendasPageCache instance = VendasPageCache._internal();

  VendasPageCache._internal();

  FaturamentoComLucro? _resumo;
  List<Empresa>? _empresasSelecionadas;
  DateTimeRange? _intervaloSelecionado;
  DateTime? _ultimaAtualizacao;

  void salvar({
    required FaturamentoComLucro resumo,
    required List<Empresa> empresas,
    required DateTimeRange intervalo,
  }) {
    _resumo = resumo;
    _empresasSelecionadas = empresas;
    _intervaloSelecionado = intervalo;
    _ultimaAtualizacao = DateTime.now();
  }

  bool get cacheValido {
    if (_ultimaAtualizacao == null) return false;
    return DateTime.now().difference(_ultimaAtualizacao!) <= const Duration(minutes: 30);
  }

  FaturamentoComLucro? get resumo => _resumo;
  List<Empresa>? get empresasSelecionadas => _empresasSelecionadas;
  DateTimeRange? get intervaloSelecionado => _intervaloSelecionado;

  void limpar() {
    _resumo = null;
    _empresasSelecionadas = null;
    _intervaloSelecionado = null;
    _ultimaAtualizacao = null;
  }
}
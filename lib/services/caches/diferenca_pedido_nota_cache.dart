import 'package:flutter/material.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/models/compras/diferenca_pedido_nota_model.dart';

/// Cache in‑memory para a tela **Diferença Pedido × Nota**.
/// Mantém os últimos resultados e filtros por até [_timeToLiveMinutes].
class DiferencaPedidoNotaPageCache {
  DiferencaPedidoNotaPageCache._internal();

  /// Instância singleton.
  static final DiferencaPedidoNotaPageCache instance =
      DiferencaPedidoNotaPageCache._internal();

  // ==================== CONFIG ====================
  /// Duração máxima do cache (minutos).
  static const int _timeToLiveMinutes = 30;

  // ==================== CAMPOS ====================
  DateTime? _timestamp;
  List<DiferencaPedidoNotaModel>? _resultados;
  Empresa? _empresaSelecionada;
  DateTimeRange? _intervaloSelecionado;
  double? _valorMinDif;
  // ==== ALTERAÇÃO 2025-07-27: agora guardamos a soma das quantidades divergentes (double, double) ====
  Map<int, (double, double)>? _contagemQtdDivergente;

  // ==================== GETTERS ====================
  /// `true` se os dados em memória ainda são válidos.
  bool get cacheValido {
    if (_timestamp == null) return false;
    final diff = DateTime.now().difference(_timestamp!);
    return diff.inMinutes < _timeToLiveMinutes &&
        _resultados != null &&
        _empresaSelecionada != null &&
        _intervaloSelecionado != null &&
        _valorMinDif != null;
  }

  List<DiferencaPedidoNotaModel>? get resultados => _resultados;

  Empresa? get empresaSelecionada => _empresaSelecionada;

  DateTimeRange? get intervaloSelecionado => _intervaloSelecionado;

  double? get valorMinDif => _valorMinDif;

  Map<int, (double, double)>? get contagemQtdDivergente => _contagemQtdDivergente;

  // ==================== AÇÕES ====================
  /// Salva uma nova fotografia no cache.
  void salvar({
    required List<DiferencaPedidoNotaModel> resultados,
    required Empresa empresa,
    required DateTimeRange intervalo,
    required double valorMinDif,
    Map<int, (double, double)>? contagemQtdDivergente,
  }) {
    _timestamp = DateTime.now();
    _resultados = List<DiferencaPedidoNotaModel>.from(resultados);
    _empresaSelecionada = empresa;
    _intervaloSelecionado = intervalo;
    _valorMinDif = valorMinDif;
    _contagemQtdDivergente = contagemQtdDivergente != null
        ? Map<int, (double, double)>.from(contagemQtdDivergente)
        : null;
  }

  /// Limpa todos os dados armazenados.
  void limpar() {
    _timestamp = null;
    _resultados = null;
    _empresaSelecionada = null;
    _intervaloSelecionado = null;
    _valorMinDif = null;
    _contagemQtdDivergente = null;
  }
}
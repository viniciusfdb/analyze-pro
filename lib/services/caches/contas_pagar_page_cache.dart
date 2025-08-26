import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:flutter/material.dart';

class ContasPagarPageCache {
  ContasPagarPageCache._internal();
  static final ContasPagarPageCache instance =
  ContasPagarPageCache._internal();

  static const _ttlMinutes = 30;

  DateTime? _timestamp;
  Map<String, Map<String, dynamic>>? _resumos;
  Empresa? _empresaSelecionada;
  DateTimeRange? _intervaloSelecionado;

  bool get cacheValido {
    if (_timestamp == null) return false;
    return DateTime.now().difference(_timestamp!).inMinutes < _ttlMinutes &&
        _resumos != null &&
        _empresaSelecionada != null &&
        _intervaloSelecionado != null;
  }

  Map<String, Map<String, dynamic>>? get resumos => _resumos;
  Empresa? get empresaSelecionada => _empresaSelecionada;
  DateTimeRange? get intervaloSelecionado => _intervaloSelecionado;

  void salvar({
    required Map<String, Map<String, dynamic>> resumos,
    required Empresa empresa,
    required DateTimeRange intervalo,
  }) {
    _timestamp = DateTime.now();
    _resumos = Map<String, Map<String, dynamic>>.from(resumos);
    _empresaSelecionada = empresa;
    _intervaloSelecionado = intervalo;
  }

  void limpar() {
    _timestamp = null;
    _resumos = null;
    _empresaSelecionada = null;
    _intervaloSelecionado = null;
  }
}
import 'package:flutter/material.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

class ContasReceberPageCache {
  ContasReceberPageCache._internal();
  static final ContasReceberPageCache instance =
  ContasReceberPageCache._internal();

  // Duração máxima do cache (minutos)
  static const _timeToLiveMinutes = 30;

  DateTime? _timestamp;
  Map<String, Map<String, dynamic>>? _resumos;
  Empresa? _empresaSelecionada;
  DateTimeRange? _intervaloSelecionado;

  bool get cacheValido {
    if (_timestamp == null) return false;
    final diff = DateTime.now().difference(_timestamp!);
    return diff.inMinutes < _timeToLiveMinutes &&
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
    this._timestamp = DateTime.now();
    this._resumos = Map<String, Map<String, dynamic>>.from(resumos);
    this._empresaSelecionada = empresa;
    this._intervaloSelecionado = intervalo;
  }

  void limpar() {
    _timestamp = null;
    _resumos = null;
    _empresaSelecionada = null;
    _intervaloSelecionado = null;
  }
}
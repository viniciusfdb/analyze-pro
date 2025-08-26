// ============================================================================
// inadimplencia_cache.dart
// ----------------------------------------------------------------------------
// 28‑06‑2025  –  Singleton para armazenar o estado compartilhado da tela
// “Inadimplência”. Evita chamadas duplicadas, reaproveita filtros e mantém
// caches com TTL de 30 minutos.
//
// COMO USAR:
//
//   final _cache = InadimplenciaCache.instance;
//
//   // Empresas --------------------------------------------------------------
//   if (_cache.empresasValidas) { .. } else { _cache.setEmpresas(empresas); }
//
//   // Resultado -------------------------------------------------------------
//   if (_cache.resultadoValido(empresa, mes)) { .. } else { _cache.setResultado(...); }
//
//   // Requisição única ------------------------------------------------------
//   if (_cache.globalFetching && _cache.globalFuture != null) await _cache.globalFuture;
//
//   _cache.globalFetching = true;
//   _cache.globalFuture = () async { ... }();
// ============================================================================

import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/models/financeiro/inadimplencia.dart';

class InadimplenciaCache {
  InadimplenciaCache._();
  static final InadimplenciaCache instance = InadimplenciaCache._();

  // -------------------------------------------------------------------------
  // Requisição única (evita chamadas duplicadas)
  // -------------------------------------------------------------------------
  bool globalFetching = false;
  Future<void>? globalFuture;

  // -------------------------------------------------------------------------
  // Cache da lista de empresas
  // -------------------------------------------------------------------------
  List<Empresa>? _cachedEmpresas;
  DateTime? _empTimestamp;
  final int _empTtlMin = 30;

  bool get empresasValidas =>
      _cachedEmpresas != null &&
      _empTimestamp != null &&
      DateTime.now().difference(_empTimestamp!).inMinutes < _empTtlMin;

  List<Empresa>? get cachedEmpresas => _cachedEmpresas;

  void setEmpresas(List<Empresa> lista) {
    _cachedEmpresas = List<Empresa>.from(lista);
    _empTimestamp = DateTime.now();
  }

  // -------------------------------------------------------------------------
  // Cache do resumo de inadimplência
  // -------------------------------------------------------------------------
  Inadimplencia? _cachedResumo;
  DateTime? _resTimestamp;
  Empresa? _resEmpresa;
  String? _resMes; // formato MM/yyyy
  bool _cachedHojeFinal = false; // se usou hoje como data final
  final int _resTtlMin = 30;

  bool resultadoValido(Empresa empresa, String mes, bool hojeFinal) =>
      _cachedResumo != null &&
      _resTimestamp != null &&
      DateTime.now().difference(_resTimestamp!).inMinutes < _resTtlMin &&
      empresa.id == _resEmpresa?.id &&
      mes == _resMes &&
      hojeFinal == _cachedHojeFinal;

  Inadimplencia? get cachedResumo => _cachedResumo;

  void setResultado({
    required Inadimplencia resumo,
    required Empresa empresa,
    required String mes,
    required bool hojeFinal,
  }) {
    _cachedResumo = resumo;
    _resTimestamp = DateTime.now();
    _resEmpresa = empresa;
    _resMes = mes;
    _cachedHojeFinal = hojeFinal;
  }

  // -------------------------------------------------------------------------
  // Memória dos filtros selecionados
  // -------------------------------------------------------------------------
  Empresa? lastEmpresa;
  String? lastMes;
  bool? lastHojeFinal;
}
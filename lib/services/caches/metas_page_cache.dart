// === 22-06-2025: Cache da tela Metas

class MetasPageCache {
  MetasPageCache._internal();
  static final MetasPageCache instance = MetasPageCache._internal();

  static const _ttlMinutes = 30;

  DateTime? _timestamp;
  String? _mesSelecionado;
  Map<int, String>? _empresas;
  Map<int, double>? _metasTotais;
  Map<int, double>? _faturamentos;

  bool get cacheValido {
    if (_timestamp == null) return false;
    return DateTime.now().difference(_timestamp!).inMinutes < _ttlMinutes &&
        _mesSelecionado != null &&
        _empresas != null &&
        _metasTotais != null &&
        _faturamentos != null;
  }

  String? get mesSelecionado => _mesSelecionado;
  Map<int, String> get empresas => _empresas ?? {};
  Map<int, double> get metasTotais => _metasTotais ?? {};
  Map<int, double> get faturamentos => _faturamentos ?? {};

  void salvar({
    required String mesSelecionado,
    required Map<int, String> empresas,
    required Map<int, double> metasTotais,
    required Map<int, double> faturamentos,
  }) {
    _timestamp       = DateTime.now();
    _mesSelecionado  = mesSelecionado;
    _empresas        = Map<int, String>.from(empresas);
    _metasTotais     = Map<int, double>.from(metasTotais);
    _faturamentos    = Map<int, double>.from(faturamentos);
  }

  void limpar() {
    _timestamp      = null;
    _mesSelecionado = null;
    _empresas       = null;
    _metasTotais    = null;
    _faturamentos   = null;
  }
}
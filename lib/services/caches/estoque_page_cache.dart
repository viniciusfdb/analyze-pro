// === 22-06-2025: Cache da tela Estoque
import '../../../models/cadastros/cad_lojas.dart';

class EstoquePageCache {
  EstoquePageCache._internal();
  static final EstoquePageCache instance = EstoquePageCache._internal();

  static const _ttlMinutes = 30;

  DateTime? _timestamp;
  Empresa? _empresaSelecionada;
  double? _qtd;
  double? _valor;
  double? _custo;

  bool get cacheValido {
    if (_timestamp == null) return false;
    return DateTime.now().difference(_timestamp!).inMinutes < _ttlMinutes &&
        _empresaSelecionada != null &&
        _qtd != null &&
        _valor != null &&
        _custo != null;
  }

  Empresa? get empresaSelecionada => _empresaSelecionada;
  double get qtd => _qtd ?? 0.0;
  double get valor => _valor ?? 0.0;
  double get custo => _custo ?? 0.0;

  void salvar({
    required Empresa empresa,
    required double qtd,
    required double valor,
    required double custo,
  }) {
    _timestamp = DateTime.now();
    _empresaSelecionada = empresa;
    _qtd = qtd;
    _valor = valor;
    _custo = custo;
  }

  void limpar() {
    _timestamp = null;
    _empresaSelecionada = null;
    _qtd = _valor = _custo = null;
  }
}
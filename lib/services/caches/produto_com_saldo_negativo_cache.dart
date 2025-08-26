import 'package:analyzepro/models/cadastros/cad_lojas.dart';

import '../../models/estoque/produto_com_saldo_negativo_model.dart';

class ProdutoComSaldoNegativoCache {
  static final ProdutoComSaldoNegativoCache instance = ProdutoComSaldoNegativoCache._internal();

  ProdutoComSaldoNegativoCache._internal();

  List<Empresa>? cachedEmpresas;
  DateTime? empresasTimestamp;
  final int empresasTtlMin = 30;

  final Map<String, List<ProdutoComSaldoNegativo>> _cachedProdutos = {};
  final Map<String, DateTime> _produtosTimestamps = {};
  final int produtosTtlMin = 30;

  Empresa? lastEmpresaSelecionada;

  void setEmpresas(List<Empresa> empresas) {
    cachedEmpresas = empresas;
    empresasTimestamp = DateTime.now();
  }

  String _gerarChave(int idEmpresa, DateTime data, String flagInativo) {
    final dataFormatada = "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}";
    return "$idEmpresa|$dataFormatada|$flagInativo";
  }

  void setProdutos(int idEmpresa, DateTime data, String flagInativo, List<ProdutoComSaldoNegativo> produtos) {
    final chave = _gerarChave(idEmpresa, data, flagInativo);
    _cachedProdutos[chave] = produtos;
    _produtosTimestamps[chave] = DateTime.now();
  }

  List<ProdutoComSaldoNegativo>? getProdutos(int idEmpresa, DateTime data, String flagInativo) {
    final chave = _gerarChave(idEmpresa, data, flagInativo);
    final produtos = _cachedProdutos[chave];
    final timestamp = _produtosTimestamps[chave];
    if (produtos != null && timestamp != null) {
      final diff = DateTime.now().difference(timestamp);
      if (diff.inMinutes < produtosTtlMin) {
        return produtos;
      }
    }
    return null;
  }

  void clear() {
    cachedEmpresas = null;
    empresasTimestamp = null;
    lastEmpresaSelecionada = null;
    _cachedProdutos.clear();
    _produtosTimestamps.clear();
  }
}
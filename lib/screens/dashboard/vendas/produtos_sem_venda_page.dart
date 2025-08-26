import 'dart:async';
import 'package:flutter/material.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import 'package:analyzepro/models/vendas/produto_sem_venda.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/repositories/vendas/produtos_sem_venda_repository.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/caches/produtos_sem_venda_cache.dart';
import '../../../api/api_client.dart';
import '../../home/menu_principal_page.dart';

class ProdutosSemVendaPage extends StatefulWidget {
  const ProdutosSemVendaPage({Key? key}) : super(key: key);

  @override
  _ProdutosSemVendaPageState createState() => _ProdutosSemVendaPageState();
}

class _ProdutosSemVendaPageState extends State<ProdutosSemVendaPage> with WidgetsBindingObserver {
  // Exibir produtos críticos
  bool _exibindoCriticos = false;

  List<ProdutoSemVenda> get _produtosCriticos => _allProdutosSemVenda.where((p) =>
  p.qtdatualestoque > 20 &&
      p.dias > 60 &&
      p.custoultimacompra > 5
  ).toList();
  // Filters
  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  int _diasSemVenda = 360;
  bool _groupDivisao = false;
  bool _groupSecao = true;
  String _filtroSaldoEstoque = "T"; // "T" = com saldo, "F" = sem saldo
  // Novo filtro: exibir somente produtos com saldo
  bool _exibirSomenteComSaldo = false;

  // 🔍 Busca por nome de seção/divisão
  bool _modoBusca = false;
  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';

  // Data
  final _repository = ProdutosSemVendaRepository(ApiClient(AuthService()));
  bool _isLoading = false;
  final _cache = ProdutosSemVendaCache.instance;
  bool _hasFetched = false;
  List<Map<String, dynamic>> _groupResumo = [];
  List<ProdutoSemVenda> _allProdutosSemVenda = [];

  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoExecucao;
  double? _tempoMedioEstimado;

  Timer? _cronometroTimer;
  double _cronometro = 0.0;

  // Cronômetro compartilhado entre instâncias da página
  static DateTime? _globalConsultaInicio;

  int get _totalSkus => _groupResumo.fold<int>(0, (sum, e) => sum + (e['quantidade'] as int));
  String get _top3Resumo => _groupResumo.take(3).map((e) => e[_groupDivisao ? 'divisao' : 'secao']).join('\n');

  /// Inicia ou reinicia o cronômetro visual baseado em [_globalConsultaInicio].
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
          if (!mounted || _globalConsultaInicio == null) return;
          final elapsedMs =
              DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
          setState(() => _cronometro = elapsedMs / 1000);
        });
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _termoBusca = _searchController.text.toLowerCase();
      });
    });
    WidgetsBinding.instance.addObserver(this);
    _tempoRepo = TempoExecucaoRepository();
    _loadEmpresas();
  }

  // Carrega a lista de empresas e seleciona a primeira empresa real como padrão.
  Future<void> _loadEmpresas() async {
    List<Empresa> empresas;
    final cacheOk = _cache.cachedEmpresas != null &&
        _cache.empresasTimestamp != null &&
        DateTime.now().difference(_cache.empresasTimestamp!).inMinutes < _cache.empresasTtlMin;

    if (cacheOk) {
      empresas = List<Empresa>.from(_cache.cachedEmpresas!);
    } else {
      final service = CadLojasService(ApiClient(AuthService()));
      empresas = await service.getEmpresasComNome();
      _cache.setEmpresas(empresas);
    }
    setState(() {
      _empresas = empresas;
      // Insere o item fictício "0 - Todas as Empresas"
      _empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
      // Restaura último filtro se existir, senão primeira real
      if (_cache.lastEmpresaSelecionada != null) {
        _empresaSelecionada =
            _empresas.firstWhere(
                  (e) => e.id == _cache.lastEmpresaSelecionada!.id,
              orElse: () => empresas.first,
            );
        _diasSemVenda   = _cache.lastDiasSemVenda   ?? _diasSemVenda;
      } else {
        _empresaSelecionada =
        _empresas.length > 1 ? _empresas[1] : _empresas.first;
      }
      _cache.lastEmpresaSelecionada = _empresaSelecionada;
    });
    await _inicializarTempoExecucao();
    await _loadData();
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresaSelecionada == null) return;
    final chave = '${_empresaSelecionada!.id}';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoExecucao = ultimo;
        _tempoMedioEstimado = media;
      });
    }
  }

  Future<void> _loadData() async {
    if (_empresaSelecionada == null) return;
    setState(() {
      _isLoading = true;
    });
    setState(() {
      _tempoExecucao = null;
    });
    final stopwatch = Stopwatch()..start();
    bool consultaNecessaria = true;
    if (_cache.globalFetching && _cache.globalFuture != null) {
      // Há uma consulta em andamento — mantemos o cronômetro ativo
      _startCronometro();
      await _cache.globalFuture;

      // Após a conclusão, restaura os dados do cache para esta instância
      if (_cache.cachedLista != null) {
        _allProdutosSemVenda =
        List<ProdutoSemVenda>.from(_cache.cachedLista!);
        _hasFetched = true;
        _applyGrouping();
      }

      // Finaliza UI
      _cronometroTimer?.cancel();
      _globalConsultaInicio = null;
      setState(() => _isLoading = false);

      // Atualiza tempos
      final chave = '${_empresaSelecionada!.id}';
      _tempoMedioEstimado = await _tempoRepo.buscarTempoMedio(chave);
      _tempoExecucao = null; // já mostrada na instância original

      return;
    }
    _cache.globalFetching = true;

    // Memorizar filtros ao iniciar busca
    _cache.lastEmpresaSelecionada = _empresaSelecionada;
    _cache.lastDiasSemVenda       = _diasSemVenda;

    final cacheListaOk = _cache.cachedLista != null &&
        _cache.listaTimestamp != null &&
        DateTime.now().difference(_cache.listaTimestamp!).inMinutes < _cache.listaTtlMin &&
        _cache.listaEmpresas != null &&
        _cache.listaEmpresas!.length == 1 &&
        _cache.listaEmpresas!.first == _empresaSelecionada!.id &&
        _cache.listaDias == _diasSemVenda &&
        _cache.listaFiltroSaldo == _filtroSaldoEstoque;

    // --- Novo controle de cronômetro -------------------------------------
    if (!cacheListaOk) {
      if (_globalConsultaInicio == null) {
        _cronometro = 0.0;
        _globalConsultaInicio = DateTime.now();
      }
      _startCronometro();
    } else {
      _cronometroTimer?.cancel();
      _globalConsultaInicio = null;
      _cronometro = 0.0;
    }
    // ---------------------------------------------------------------------

    if (cacheListaOk) {
      setState(() {
        _allProdutosSemVenda = List<ProdutoSemVenda>.from(_cache.cachedLista!);
        _isLoading = false;
        _hasFetched = true;
      });
      _applyGrouping();
      consultaNecessaria = false;
      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final chave = '${_empresaSelecionada!.id}';
      _tempoExecucao = tempoMs / 1000;
      _tempoMedioEstimado = await _tempoRepo.buscarTempoMedio(chave);
      _cache.globalFetching = false;
      return;
    }

    // Inicia o cronômetro apenas quando for buscar dados da API

    _cache.globalFuture = () async {
      try {
        List<ProdutoSemVenda> items = [];
        if (_empresaSelecionada!.id == 0) {
          for (var empresa in _empresas.where((e) => e.id != 0)) {
            final partial = await _repository.getProdutosSemVenda(
              empresas: [empresa.id],
              dias: _diasSemVenda,
              saldoEstoque: _filtroSaldoEstoque,
            );
            items.addAll(partial);
          }
        } else {
          items = await _repository.getProdutosSemVenda(
            empresas: [_empresaSelecionada!.id],
            dias: _diasSemVenda,
            saldoEstoque: _filtroSaldoEstoque,
          );
        }

        _cache.setResultado(
          lista: items,
          empresas: [_empresaSelecionada!.id],
          dias: _diasSemVenda,
          filtroSaldo: _filtroSaldoEstoque,
        );

        _allProdutosSemVenda = items;
        _hasFetched = true;
        _applyGrouping();
      } finally {
        stopwatch.stop();
        final tempoMs = stopwatch.elapsedMilliseconds;
        final chave = '${_empresaSelecionada!.id}';
        final tempoReal = tempoMs / 1000;
        if (consultaNecessaria) {
          await _tempoRepo.salvarTempo(chave, tempoMs);
        }
        final media = await _tempoRepo.buscarTempoMedio(chave);
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        if (mounted) {
          setState(() {
            _tempoExecucao = tempoReal;
            _tempoMedioEstimado = media;
          });
        }
        _cache.globalFetching = false;
        _cache.globalFuture = null;
      }
      @override
      void dispose() {
        _searchController.dispose();
        _cronometroTimer?.cancel();
        WidgetsBinding.instance.removeObserver(this);
        super.dispose();
      }
    }();

    await _cache.globalFuture;
  }

  void _applyGrouping() {
    // ALTERADO: Agrupamento e resumo apenas por dias sem venda
    final Map<int, List<ProdutoSemVenda>> groups = {};
    for (var item in _allProdutosSemVenda) {
      final key = _groupSecao ? item.idsecao : item.iddivisao;
      groups.putIfAbsent(key, () => []).add(item);
    }
    final resumo = groups.entries.map((e) {
      final list = e.value;
      // ALTERADO: Removido cálculo de balanço, só média de dias sem venda
      return {
        _groupSecao ? 'idsecao' : 'iddivisao': e.key,
        _groupSecao ? 'secao' : 'divisao': _groupSecao ? list.first.descrsecao : list.first.descrdivisao,
        'quantidade': list.length,
        'mediaDiasVenda': list.fold<int>(0, (s, x) => s + x.dias) / list.length,
      };
    }).toList()
      ..sort((a, b) => (b['quantidade'] as int).compareTo(a['quantidade'] as int));
    setState(() {
      _groupResumo = resumo;
      _isLoading = false;
    });
  }


  void _showSectionItems(String secao, List<ProdutoSemVenda> items) {
    // ALTERADO: Detalhamento exibe apenas dias sem venda
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$secao (${items.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, idx) {
                        final p = items[idx];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p.idproduto} - ${p.descricao.trim()}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 20, color: Color(0xFF2E7D32)),
                                  const SizedBox(width: 6),
                                  const Text('Dias sem venda: '),
                                  Text(
                                    '${p.dias}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.inventory, size: 20, color: Colors.orange),
                                  const SizedBox(width: 6),
                                  Text('Estoque: ${p.qtdatualestoque.toStringAsFixed(0)}'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.attach_money, size: 20, color: Colors.blue),
                                  const SizedBox(width: 6),
                                  Text('Preço de venda: R\$ ${p.valprecovarejo.toStringAsFixed(2)}'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.shopping_cart, size: 20, color: Colors.redAccent),
                                  const SizedBox(width: 6),
                                  Text('Custo última compra: R\$ ${p.custoultimacompra.toStringAsFixed(2)}'),
                                ],
                              ),
                              if (p.dtultimavenda != "1900-01-01" && p.dtultimavenda.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.history, size: 20, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text('Última venda: ${p.dtultimavenda}'),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              // Linha removida: divisao/secao/grupo em cinza
                              // Text(
                              //   '${p.descrdivisao} / ${p.descrsecao} / ${p.descrgrupo}',
                              //   style: const TextStyle(fontSize: 12, color: Colors.grey),
                              // ),
                              const Divider(height: 16),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Fechar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build KPI cards data
  List<Map<String, dynamic>> _buildCards() {
    final baseCards = [
      {
        'title': 'Total de SKUs',
        'value': '$_totalSkus',
        'icon': Icons.inventory_2,
      },
      {
        'title': _groupDivisao ? 'Top 3 Divisões' : 'Top 3 Seções',
        'value': _top3Resumo,
        'icon': Icons.leaderboard,
      },
      // Card "Exibir Críticos" removido
    ];
    return baseCards;
  }

  @override
  Widget build(BuildContext context) {
    final cards = _buildCards();
    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu), onPressed: ()=>Scaffold.of(context).openDrawer(),
          ),
        ),
        //title: const Text('Produtos Sem Venda'),
        actions: const [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filters row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Empresa selector
                if (_empresas.isNotEmpty)
                  IgnorePointer(
                    ignoring: _isLoading,
                    child: Opacity(
                      opacity: _isLoading ? 0.5 : 1.0,
                      child: PopupMenuButton<Empresa>(
                        itemBuilder: (_) => _empresas.map((e) =>
                            PopupMenuItem(value: e, child: Text(e.toString()))
                        ).toList(),
                        onSelected: (e) async {
                          if (_isLoading) return;
                          setState(() => _empresaSelecionada = e);
                          await _inicializarTempoExecucao();
                          _loadData();
                        },
                        child: TextButton.icon(
                          icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                          label: Text(
                            _empresaSelecionada?.nome ?? 'Empresa',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black87),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: null,
                        ),
                      ),
                    ),
                  ),
                // Dias sem Venda slider with value
                IgnorePointer(
                  ignoring: _isLoading,
                  child: Opacity(
                    opacity: _isLoading ? 0.5 : 1.0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Dias sem Venda:'),
                        Slider(
                          value: _diasSemVenda.toDouble(),
                          min: 10, max: 1000, divisions: 99,
                          label: '$_diasSemVenda',
                          onChanged: (v) {
                            if (_isLoading) return;
                            setState(() => _diasSemVenda = v.toInt());
                          },
                          onChangeEnd: (_) {
                            if (_isLoading) return;
                            _loadData();
                          },
                        ),
                        Text('$_diasSemVenda'),
                      ],
                    ),
                  ),
                ),
                // Grouping chips and estoque controls
                Wrap(
                  spacing: 6,
                  children: [
                    // Chip Seção
                    FilterChip(
                      label: const Text('Seção'),
                      selected: _groupSecao,
                      onSelected: (v) {
                        if (_isLoading) return;
                        setState(() {
                          if (v) {
                            _groupSecao = true;
                            _groupDivisao = false;
                          } else {
                            _groupSecao = false;
                            _groupDivisao = true;
                          }
                        });
                        if (!_hasFetched) {
                          _loadData();
                        } else {
                          setState(() {
                            _isLoading = true;
                          });
                          _applyGrouping();
                        }
                      },
                      backgroundColor: Colors.grey.shade200,
                      selectedColor: Colors.grey.shade200,
                      checkmarkColor: Colors.black87,
                      labelStyle: const TextStyle(color: Colors.black87),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: _groupSecao ? Colors.black87 : Colors.transparent,
                          width: 0,
                        ),
                      ),
                    ),
                    // Chip Divisão
                    FilterChip(
                      label: const Text('Divisão'),
                      selected: _groupDivisao,
                      onSelected: (v) {
                        if (_isLoading) return;
                        setState(() {
                          if (v) {
                            _groupDivisao = true;
                            _groupSecao = false;
                          } else {
                            _groupDivisao = false;
                            _groupSecao = true;
                          }
                        });
                        if (!_hasFetched) {
                          _loadData();
                        } else {
                          setState(() {
                            _isLoading = true;
                          });
                          _applyGrouping();
                        }
                      },
                      backgroundColor: Colors.grey.shade200,
                      selectedColor: Colors.grey.shade200,
                      checkmarkColor: Colors.black87,
                      labelStyle: const TextStyle(color: Colors.black87),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: _groupDivisao ? Colors.black87 : Colors.transparent,
                          width: 0,
                        ),
                      ),
                    ),
                    // Estoque filter icon button (adicionado ao final do primeiro Wrap)
                    IconButton(
                      onPressed: _isLoading ? null : () {
                        setState(() {
                          _filtroSaldoEstoque = _filtroSaldoEstoque == "T" ? "F" : "T";
                        });

                        final textoSnackBar = _filtroSaldoEstoque == "T"
                            ? '🔄 Apenas produtos COM saldo de estoque.'
                            : '🔄 Apenas produtos SEM saldo de estoque.';

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(textoSnackBar),
                            duration: const Duration(seconds: 2),
                          ),
                        );

                        _loadData(); // Garante que a consulta será atualizada
                      },
                      tooltip: _filtroSaldoEstoque == "T"
                          ? "Somente produtos com saldo em estoque"
                          : "Somente produtos SEM saldo em estoque",
                      icon: Icon(
                        _filtroSaldoEstoque == "T"
                            ? Icons.inventory_2
                            : Icons.inventory_2_outlined,
                        color: _filtroSaldoEstoque == "T"
                            ? Color(0xFF2E7D32)
                            : Colors.grey[700],
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    // ALTERADO: Título não menciona balanço
                    text: 'Produtos Sem Venda',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: '  ${_cronometro.toStringAsFixed(1)}s',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  if (_tempoMedioEstimado != null)
                    TextSpan(
                      text: ' (~${_tempoMedioEstimado!.toStringAsFixed(1)}s)',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // KPI cards
            GridView.builder(
              itemCount: cards.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.4
              ),
              itemBuilder: (context, i) {
                if (_isLoading) {
                  return Container(
                    constraints: const BoxConstraints(minHeight: 340),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final card = cards[i];
                return _DashboardCard(
                  title: card['title'] as String,
                  value: card['value'] as String,
                  icon: card['icon'] as IconData,
                  onTap: card.containsKey('onTap') ? card['onTap'] as VoidCallback : null,
                );
              },
            ),
            const SizedBox(height: 0),
            Row(
              children: [
                Expanded(
                  child: _modoBusca
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Filtrar...',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          ),
                        )
                      : Text(
                          _groupSecao ? 'Lista de Seções' : 'Lista de Divisões',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(width: 6),
                if (_produtosCriticos.isNotEmpty)
                  // Localizado o IconButton dos críticos aqui, com novo ícone conforme solicitado
                  IconButton(
                    icon: Icon(
                      Icons.warning_amber_rounded,
                      color: _exibindoCriticos ? Colors.orange : Colors.grey,
                    ),
                    tooltip: 'Itens críticos - 60 dsv, est > 20, custo > 5',
                    onPressed: () {
                      setState(() {
                        _exibindoCriticos = !_exibindoCriticos;
                      });
                    },
                  ),
                IconButton(
                  icon: Icon(_modoBusca ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      if (_modoBusca) {
                        _modoBusca = false;
                        _searchController.clear();
                        _termoBusca = '';
                      } else {
                        _modoBusca = true;
                      }
                    });
                  },
                ),
              ],
            ),
            // Removido o SizedBox(height: 6) abaixo do título da lista
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              const SizedBox(height: 0),
              Builder(
                builder: (_) {
                  final term = _termoBusca.trim();
                  final List<Map<String, dynamic>> entries;
                  if (_exibindoCriticos) {
                    final Map<int, List<ProdutoSemVenda>> groups = {};
                    for (var item in _produtosCriticos) {
                      final key = _groupSecao ? item.idsecao : item.iddivisao;
                      groups.putIfAbsent(key, () => []).add(item);
                    }
                    entries = groups.entries.map((e) {
                      final list = e.value;
                      return {
                        _groupSecao ? 'idsecao' : 'iddivisao': e.key,
                        _groupSecao ? 'secao' : 'divisao': _groupSecao ? list.first.descrsecao : list.first.descrdivisao,
                        'quantidade': list.length,
                        'mediaDiasVenda': list.fold<int>(0, (s, x) => s + x.dias) / list.length,
                      };
                    }).toList()
                      ..sort((a, b) => (b['quantidade'] as int).compareTo(a['quantidade'] as int));
                  } else {
                    entries = _groupResumo.where((e) {
                      final nome = (_groupSecao ? e['secao'] : e['divisao']).toString().toLowerCase();
                      return nome.contains(term);
                    }).toList();
                  }
                  return GridView.builder(
                    itemCount: entries.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.6,
                    ),
                    itemBuilder: (context, idx) {
                      final entry = entries[idx];
                      final key = _groupDivisao ? entry['divisao'] : entry['secao'];
                      final count = entry['quantidade'];
                      final avgVenda = (entry['mediaDiasVenda'] as num).toDouble();

                      return InkWell(
                        onTap: () {
                          final idKey = _groupSecao ? entry['idsecao'] as int : entry['iddivisao'] as int;
                          final filtered = (_exibindoCriticos ? _produtosCriticos : _allProdutosSemVenda)
                              .where((item) => (_groupSecao ? item.idsecao : item.iddivisao) == idKey)
                              .toList();
                          filtered.sort((a, b) {
                            final cmpDias = b.dias.compareTo(a.dias);
                            return cmpDias;
                          });
                          _showSectionItems(key, filtered);
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 100),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                key,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.format_list_bulleted, size: 18, color: Color(0xFF2E7D32)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$count itens',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${avgVenda.toStringAsFixed(0)}d s/ venda',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  const _DashboardCard({
    Key? key,
    required this.title,
    required this.value,
    this.icon,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon!, color: const Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

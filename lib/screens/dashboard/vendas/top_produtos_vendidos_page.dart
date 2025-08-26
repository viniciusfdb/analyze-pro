import 'package:flutter/material.dart';
import 'package:analyzepro/services/caches/top_produtos_vendidos_cache.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import 'package:analyzepro/models/vendas/estruturamercadologica/vendas_por_produto_model.dart';
import '../../../repositories/vendas/estruturamercadologica/vendas_por_produto_repository.dart';
import '../../home/menu_principal_page.dart';

class TopProdutosVendidos extends StatefulWidget {
  const TopProdutosVendidos({super.key});

  @override
  State<TopProdutosVendidos> createState() => _TopProdutosVendidosState();
}

class _TopProdutosVendidosState extends State<TopProdutosVendidos> {
  // CACHE DE EMPRESAS (TTL 30 min)
  static List<Empresa>? _cachedEmpresas;
  static DateTime? _empresasTimestamp;
  static const int _empresasTtlMin = 30;

  // CONTROLE DE CHAMADAS CONCORRENTES
  static Future<void>? _produtosFuture;
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final CadLojasService _cadLojasService;
  late final VendasPorProdutoRepository _repo;

  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  static DateTime? _globalConsultaInicio;
  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoExecucao;
  double? _tempoMedioEstimado;

  // Memoriza filtros entre navegações
  static List<int>? _lastEmpresasSelecionadasIds;
  static DateTimeRange? _lastDateRangeSelecionada;

  // Cache de página para persistência completa
  static final _pageCache = TopProdutosVendidosCache.instance;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;

  List<VendaPorProdutoModel> _produtos = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Instância única de serviços
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _cadLojasService = CadLojasService(_apiClient);
    _repo = VendasPorProdutoRepository(_apiClient);
    _tempoRepo = TempoExecucaoRepository();

    // Carrega empresas com cache, depois já busca histórico do tempo médio
    _carregarEmpresas().then((_) {
      _buscarTempoMedio();
    });
  }

  Future<void> _buscarTempoMedio() async {
    if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) return;
    final idsOrdenados = _empresasSelecionadas.map((e) => e.id).toList()..sort();
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${idsOrdenados.join(",")}|$dias|top_produtos';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoMedioEstimado = media;
      });
    }
  }

  void _carregarProdutosDoCache() {
    final cache = TopProdutosVendidosCache.instance;
    if (cache.cacheValido) {
      final idsEmp = _empresasSelecionadas.map((e) => e.id).toList();
      final mesmaEmpresa = ListEquality().equals(
        idsEmp,
        cache.empresasSelecionadas?.map((e) => e.id).toList(),
      );
      final mesmoIntervalo = cache.intervaloSelecionado == _selectedDateRange;
      if (mesmaEmpresa && mesmoIntervalo) {
        setState(() {
          _produtos = cache.produtos ?? [];
          _tempoExecucao = cache.tempoExecucao;
          _tempoMedioEstimado = cache.tempoMedioEstimado;
        });
      }
    }
  }

  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsed = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() => _cronometro = elapsed / 1000);
    });
  }

  /// Carrega empresas e restaura seleção de filtros.
  Future<void> _carregarEmpresas() async {
    // Se há consulta em andamento, restaura filtros e aguarda
    if (_produtosFuture != null) {
      final empresas = await _cadLojasService.getEmpresasComNome();
      if (empresas.isNotEmpty && empresas.first.id != 0) {
        empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
      }
      List<Empresa> selecionadas;
      if (_lastEmpresasSelecionadasIds != null) {
        selecionadas = empresas.where((e) => _lastEmpresasSelecionadasIds!.contains(e.id)).toList();
      } else if (empresas.length > 1) {
        selecionadas = empresas.where((e) => e.id != 0).toList();
      } else {
        selecionadas = List.from(empresas);
      }
      setState(() {
        _empresas = empresas;
        _empresasSelecionadas = selecionadas;
        _selectedDateRange = _lastDateRangeSelecionada;
        _produtos = _pageCache.itens ?? _produtos;
      });
      // retoma cronômetro
      if (_globalConsultaInicio != null) _startCronometro();
      // Aguarda a consulta pendente e limpa loader
      await _produtosFuture;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _produtosFuture = null;
        });
        // Restaura lista já processada do cache
        _carregarProdutosDoCache();
      }
      // Após restaurar filtros, buscar tempo médio
      await _buscarTempoMedio();
      return;
    }

    // Se cache de página válido, restaura todos os valores
    if (_pageCache.cacheValido) {
      final empresas = await _cadLojasService.getEmpresasComNome();
      if (empresas.isNotEmpty && empresas.first.id != 0) {
        empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
      }
      setState(() {
        _empresas = empresas;
        _empresasSelecionadas = _pageCache.empresasSelecionadas ?? [];
        _selectedDateRange = _pageCache.intervaloSelecionado;
        _produtos = _pageCache.itens ?? [];
        _tempoExecucao = _pageCache.tempoExecucao;
        _tempoMedioEstimado = _pageCache.tempoMedioEstimado;
      });
      // Após restaurar filtros, buscar tempo médio
      await _buscarTempoMedio();
      return;
    }

    // Verifica cache de empresas
    final cacheOk = _cachedEmpresas != null
        && _empresasTimestamp != null
        && DateTime.now().difference(_empresasTimestamp!).inMinutes < _empresasTtlMin;
    final empresas = cacheOk
        ? List<Empresa>.from(_cachedEmpresas!)
        : await _cadLojasService.getEmpresasComNome();
    if (!cacheOk) {
      _cachedEmpresas = List<Empresa>.from(empresas);
      _empresasTimestamp = DateTime.now();
    }
    if (empresas.isNotEmpty && empresas.first.id != 0) {
      empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }
    final now = DateTime.now();
    final bool hasPrevious = _lastEmpresasSelecionadasIds != null && _lastDateRangeSelecionada != null;
    final List<Empresa> restoredEmpresas = hasPrevious
        ? empresas.where((e) => _lastEmpresasSelecionadasIds!.contains(e.id)).toList()
        : (empresas.length > 1
            ? empresas.where((e) => e.id != 0).toList()
            : List.from(empresas));
    final DateTimeRange restoredRange = hasPrevious
        ? _lastDateRangeSelecionada!
        : DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59),
          );
    setState(() {
      _empresas = empresas;
      _empresasSelecionadas = restoredEmpresas;
      _selectedDateRange   = restoredRange;
    });
    // Depois de popular as empresas, carrega produtos e busca tempo médio
    await _buscarTempoMedio();
    // Chama _carregarProdutos() automaticamente após restaurar empresas (primeiro acesso ou sem filtros prévios)
    await _carregarProdutos();
  }

  Future<void> _carregarProdutos() {
    if (_produtosFuture != null) {
      return _produtosFuture!;
    }
    _produtosFuture = () async {
      final empresaIds = _empresasSelecionadas.map((e) => e.id).toList();

      // Evita chamada desnecessária se filtros não mudaram
      if (_lastEmpresasSelecionadasIds != null &&
          _lastDateRangeSelecionada != null &&
          ListEquality().equals(_lastEmpresasSelecionadasIds, empresaIds) &&
          _lastDateRangeSelecionada == _selectedDateRange) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Limpa lista atual e exibe loader ao iniciar nova consulta
      setState(() {
        _produtos = [];
        _isLoading = true;
      });

      if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _lastEmpresasSelecionadasIds = List.from(empresaIds);
      _lastDateRangeSelecionada = _selectedDateRange;

      _tempoExecucao = null;
      if (_globalConsultaInicio == null) {
        _cronometro = 0.0;
        _globalConsultaInicio = DateTime.now();
      }
      _startCronometro();
      final stopwatch = Stopwatch()..start();

      // 🧹 Limpa o cache ANTES de iniciar nova consulta
      TopProdutosVendidosCache.instance.limpar();

      try {
        final bool todasEmpresasSelecionadas =
            _empresasSelecionadas.any((e) => e.id == 0);

        final List<int> idsEmpresas = todasEmpresasSelecionadas
            ? _empresasSelecionadas
                .where((e) => e.id != 0)
                .map((e) => e.id)
                .toList()
            : _empresasSelecionadas.map((e) => e.id).toList();

        final Map<int, VendaPorProdutoModel> produtosAgrupados = {};

        for (final idEmpresa in idsEmpresas) {
          final dadosEmpresa = await _repo.getVendasPorProduto(
            idsEmpresa: [idEmpresa],
            idSubgrupo: null,
            dataInicial: _selectedDateRange!.start,
            dataFinal: _selectedDateRange!.end,
          );

          for (final produto in dadosEmpresa) {
            final existente = produtosAgrupados[produto.idSubproduto];
            if (existente != null) {
              produtosAgrupados[produto.idSubproduto] = existente.copyWith(
                qtdProduto: existente.qtdProduto + produto.qtdProduto,
                qtdProdutoVenda: existente.qtdProdutoVenda + produto.qtdProdutoVenda,
                valTotLiquido: existente.valTotLiquido + produto.valTotLiquido,
                lucro: existente.lucro + produto.lucro,
              );
            } else {
              produtosAgrupados[produto.idSubproduto] = produto;
            }
          }
        }

        final listaFinal = produtosAgrupados.values.toList()
          ..sort((a, b) => b.qtdProduto.compareTo(a.qtdProduto));
        final top10 = listaFinal.take(10).toList();

        stopwatch.stop();
        final tempoMs = stopwatch.elapsedMilliseconds;
        final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
        // [AJUSTE] Chave de tempo médio agora com IDs de empresas ordenados
        final idsOrdenados = List<int>.from(idsEmpresas)..sort();
        final chave = '${idsOrdenados.join(",")}|$dias|top_produtos';
        final tempoReal = (tempoMs / 1000);
        await _tempoRepo.salvarTempo(chave, tempoMs);
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          _tempoExecucao = tempoReal;
          _tempoMedioEstimado = media;
        }
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;

        setState(() {
          _produtos = top10;
          _isLoading = false;
        });
        // Persistir página completa ao final da consulta
        _pageCache.salvar(
          itens: _produtos,
          empresas: _empresasSelecionadas,
          intervalo: _selectedDateRange!,
          tempoExecucaoSegundos: _tempoExecucao ?? 0,
          tempoMedioEstimadoSegundos: _tempoMedioEstimado ?? 0,
        );
        // Atualize o state com o valor do cache
        setState(() {
          _tempoMedioEstimado = _pageCache.tempoMedioEstimado;
        });
      } catch (e) {
        // Você pode tratar erros aqui se desejar
        setState(() {
          _isLoading = false;
        });
      } finally {
        setState(() => _isLoading = false);
      }
    }();
    return _produtosFuture!.whenComplete(() {
      _produtosFuture = null;
      if (mounted) setState(() => _isLoading = false);
    });
  }

  String get _formattedDateRange {
    if (_selectedDateRange == null) return 'Selecione o intervalo';
    final start = _formatter.format(_selectedDateRange!.start);
    final end = _formatter.format(_selectedDateRange!.end);
    return '$start - $end';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _buscarTempoMedio();
      _carregarProdutos();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se houver consulta em andamento, retoma cronômetro
    if (_globalConsultaInicio != null && (_cronometroTimer == null || !_cronometroTimer!.isActive)) {
      _startCronometro();
    }
    // [AJUSTE] Filtros só habilitados quando não está carregando nem há consulta pendente
    final bool filtrosHabilitados = !_isLoading && _produtosFuture == null;
    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: const [
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [AJUSTE] Filtros só habilitados quando não está carregando nem há consulta pendente
                IgnorePointer(
                  ignoring: !filtrosHabilitados,
                  child: Opacity(
                    opacity: filtrosHabilitados ? 1 : 0.5,
                    child: PopupMenuButton<Empresa>(
                      color: Colors.white,
                      itemBuilder: (_) => _empresas
                          .map((e) => PopupMenuItem(value: e, child: Text(e.toString())))
                          .toList(),
                      onSelected: filtrosHabilitados
                          ? (empresa) {
                              setState(() {
                                _empresasSelecionadas = empresa.id == 0
                                    ? _empresas.where((e) => e.id != 0).toList()
                                    : [empresa];
                              });
                              _buscarTempoMedio();
                              _carregarProdutos();
                            }
                          : null,
                      tooltip: 'Selecionar empresa',
                      child: TextButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                        label: Text(
                          _empresasSelecionadas.isEmpty
                              ? 'Empresa'
                              : (_empresasSelecionadas.length == 1
                                  ? _empresasSelecionadas.first.toString()
                                  : 'Todas as Empresas'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // [AJUSTE] Filtros só habilitados quando não está carregando nem há consulta pendente
                IgnorePointer(
                  ignoring: !filtrosHabilitados,
                  child: Opacity(
                    opacity: filtrosHabilitados ? 1 : 0.5,
                    child: TextButton.icon(
                      onPressed: filtrosHabilitados ? _pickDateRange : null,
                      icon: const Icon(Icons.calendar_today, size: 18, color: Colors.black87),
                      label: Text(
                        _formattedDateRange,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Top 10 em Vendas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: '  ${_cronometro.toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  TextSpan(
                    text: _tempoMedioEstimado != null
                        ? ' (~${_tempoMedioEstimado!.toStringAsFixed(1)}s)'
                        : ' (…s)',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_produtos.isEmpty && (_isLoading || _produtosFuture != null))
              const Center(child: Padding(
                padding: EdgeInsets.only(top: 16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else ...[
              ListView.builder(
                itemCount: _produtos.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final produto = _produtos[index];
                  return GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
                          return Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
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
                                    produto.descricao.trim(),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInfoRow(Icons.numbers, 'Produto', produto.idProduto.toString(), iconColor: Color(0xFF2E7D32)),
                                  _buildInfoRow(Icons.category, 'Subproduto', produto.idSubproduto.toString(), iconColor: Color(0xFF2E7D32)),
                                  _buildInfoRow(Icons.shopping_cart_outlined, 'Vendido', produto.qtdProdutoVenda.toStringAsFixed(2), iconColor: Color(0xFF2E7D32)),
                                  _buildInfoRow(Icons.paid, 'Total', currency.format(produto.valTotLiquido), iconColor: Color(0xFF2E7D32)),
                                  _buildInfoRow(Icons.attach_money, 'Lucro', currency.format(produto.lucro), iconColor: Color(0xFF2E7D32)),
                                  const SizedBox(height: 24),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: const Color(0xFF2E7D32),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
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
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          )
                        ],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              produto.descricao.trim(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: produto.lucro < 0 ? Colors.red : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            produto.qtdProdutoVenda.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (_produtos.isNotEmpty && (_isLoading || _produtosFuture != null))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _buildInfoRow(IconData icon, String label, String value, {Color iconColor = Colors.black54}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    ),
  );
}
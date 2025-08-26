import 'dart:async';

import 'package:flutter/material.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';

import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/vendas/faturamento_com_lucro_model.dart';
import 'package:analyzepro/repositories/vendas/faturamento_com_lucro_repository.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/services/caches/vendas_page_cache.dart';
import 'package:analyzepro/services/auth_service.dart';
import '../../../models/cadastros/cad_lojas.dart';
import '../../home/menu_principal_page.dart';
import 'estruturamercadologica/vendas_por_divisao_page.dart';
import 'estruturamercadologica/vendas_por_secao_page.dart';
import 'estruturamercadologica/vendas_por_grupo_page.dart';
import 'estruturamercadologica/vendas_por_vendedor_page.dart';


class VendasPage extends StatefulWidget {
  final List<Empresa>? empresasPreSelecionadas;
  final DateTimeRange? intervaloPreSelecionado;

  const VendasPage({
    super.key,
    this.empresasPreSelecionadas,
    this.intervaloPreSelecionado,
  });

  @override
  State<VendasPage> createState() => _VendasPageState();
}

class _VendasPageState extends State<VendasPage> with WidgetsBindingObserver {

  // Sessão única compartilhada
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final FaturamentoComLucroRepository _fatRepo;
  late final CadLojasService _cadLojasService;

  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoExecucao;
  double? _tempoMedioEstimado;
  Timer? _cronometroTimer;
  double _cronometro = 0.0;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  // bool _usarDadosLocais = false;
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  final Map<int, bool> _cardLoadStatus = {0: true, 1: true, 2: true, 3: true, 4: true, 5: true, 6: true};
  // Indica se qualquer card ainda está carregando
  bool get _isLoading => _cardLoadStatus.values.any((v) => v == true);
  // === CONTROLE GLOBAL DE REQUISIÇÃO 25‑06‑2025 ===
  static Future<void>? _globalFuture;
  // Momento em que a consulta global começou – mantém cronômetro ativo em múltiplas instâncias
  static DateTime? _globalConsultaInicio;
  /// Inicia ou reinicia o cronômetro visual a partir de [_globalConsultaInicio].
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsed = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() {
        _cronometro = elapsed / 1000;
      });
    });
  }
  // === MEMÓRIA DOS ÚLTIMOS FILTROS EXECUTADOS 26‑06‑2025 ===
  static List<Empresa>? _lastEmpresasSelecionadas;
  static DateTimeRange? _lastIntervaloSelecionado;
  // === CACHE DE EMPRESAS (evita GET cad_lojas repetido) ===
  static List<Empresa>? _cachedEmpresas;
  static DateTime? _empresasTimestamp;
  static const _empresasTtlMin = 30; // minutos
  FaturamentoComLucro? _resumo;

  // Valores já formatados para exibir no dashboard
  String _totalVendaFmt = 'R\$ 0,00';
  String _lucroFmt = 'R\$ 0,00';
  String _totalVendaBrutaFmt = 'R\$ 0,00';
  String _lucroBrutoFmt = 'R\$ 0,00';
  String _devolucoesFmt = 'R\$ 0,00';
  String _ticketMedioFmt = 'R\$ 0,00';
  String _nroVendasFmt = '0';
  String _lucroPercentFmt = '';          // novo: percentual de lucro em texto
  String _lucroBrutoPercentFmt = '';     // novo: percentual de lucro bruto

  // === ALTERAÇÃO 22-06-2025: método utilitário para recalcular os textos exibidos nos cards
  void _atualizarValoresFormatados() {
    if (_resumo == null) return;
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    _totalVendaFmt       = currency.format(_resumo!.totalVenda);
    _lucroFmt            = currency.format(_resumo!.lucro);
    // Percentual de lucro sobre a venda líquida
    _lucroPercentFmt = _resumo!.totalVenda > 0
        ? ' ${(_resumo!.lucro / _resumo!.totalVenda * 100).toStringAsFixed(1)}%'
        : '';
    _totalVendaBrutaFmt  = currency.format(_resumo!.totalVendaBruta);
    _lucroBrutoFmt       = currency.format(_resumo!.lucroBruto);
    _lucroBrutoPercentFmt = _resumo!.totalVendaBruta > 0
        ? ' ${(_resumo!.lucroBruto / _resumo!.totalVendaBruta * 100).toStringAsFixed(1)}%'
        : '';
    _devolucoesFmt       = currency.format(_resumo!.devolucoes);
    _ticketMedioFmt      = currency.format(_resumo!.ticketMedio);
    _nroVendasFmt        = _resumo!.nroVendas.toString();
  }

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _fatRepo = FaturamentoComLucroRepository(_apiClient);
    _cadLojasService = CadLojasService(_apiClient);

    _tempoRepo = TempoExecucaoRepository();

    WidgetsBinding.instance.addObserver(this);

    _carregarEmpresas();
  }

  @override
  void dispose() {
    _cronometroTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cronometroTimer?.cancel();
    } else if (state == AppLifecycleState.resumed &&
        (_cronometroTimer == null || !_cronometroTimer!.isActive)) {
      _startCronometro();
    }
  }

  Future<void> _carregarEmpresas() async {
    List<Empresa> empresas;

    // Aproveita cache local se ainda válido
    final cacheOk = _cachedEmpresas != null &&
        _empresasTimestamp != null &&
        DateTime.now().difference(_empresasTimestamp!).inMinutes < _empresasTtlMin;

    if (cacheOk) {
      empresas = List<Empresa>.from(_cachedEmpresas!);
    } else {
      empresas = await _cadLojasService.getEmpresasComNome();
      _cachedEmpresas   = List<Empresa>.from(empresas);
      _empresasTimestamp = DateTime.now();
    }

    // Evita inserir duplicado do “Todas as Empresas”
    if (empresas.isEmpty || empresas.first.id != 0) {
      empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }

    // Se há requisição global em andamento, mostra loaders e aguarda
    if (_globalFuture != null) {
      for (final key in _cardLoadStatus.keys) {
        _cardLoadStatus[key] = true;
      }
      _startCronometro();
      if (mounted) {
        setState(() {
          _empresas = empresas;
          _empresasSelecionadas = _lastEmpresasSelecionadas ??
              VendasPageCache.instance.empresasSelecionadas ?? [];
          _selectedDateRange = _lastIntervaloSelecionado ??
              VendasPageCache.instance.intervaloSelecionado;
        });
      }
      await _globalFuture;
      for (final key in _cardLoadStatus.keys) {
        _cardLoadStatus[key] = false;
      }
      if (mounted) {
        _resumo = VendasPageCache.instance.resumo;
        _atualizarValoresFormatados();
        setState(() {
          _empresasSelecionadas = _lastEmpresasSelecionadas ??
              VendasPageCache.instance.empresasSelecionadas ?? [];
          _selectedDateRange = _lastIntervaloSelecionado ??
              VendasPageCache.instance.intervaloSelecionado;
        });
        await _inicializarTempoExecucao();
      }
      return;
    }

    if (VendasPageCache.instance.cacheValido &&
        widget.empresasPreSelecionadas == null &&
        widget.intervaloPreSelecionado == null) {
      for (final key in _cardLoadStatus.keys) {
        _cardLoadStatus[key] = false;
      }
      if (mounted) {
        setState(() {
          _empresas = empresas;
          _empresasSelecionadas = VendasPageCache.instance.empresasSelecionadas ?? [];
          _selectedDateRange = VendasPageCache.instance.intervaloSelecionado;
          _resumo = VendasPageCache.instance.resumo;
          _atualizarValoresFormatados();
        });
        await _inicializarTempoExecucao();
      }
      return;
    }

    final hoje = DateTime.now();
    final hojeInicio = DateTime(hoje.year, hoje.month, hoje.day);
    final hojeFim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);

    if (mounted) {
      final preSel = widget.empresasPreSelecionadas;
      final preRange = widget.intervaloPreSelecionado;
      final preIds = preSel?.map((e) => e.id).toSet() ?? {};

      // Se veio empresa da Home, garante que exista nesta conexão e ignora o id 0 (Todas)
      final selecionadas = preIds.isEmpty
          ? (empresas.length > 1 ? [empresas[1]] : empresas)
          : empresas.where((e) => preIds.contains(e.id) && e.id != 0).toList();

      setState(() {
        _empresas = empresas;
        _empresasSelecionadas = selecionadas;
        _selectedDateRange = preRange ?? DateTimeRange(start: hojeInicio, end: hojeFim);
      });
    }

    await _inicializarTempoExecucao();
    _carregarDados();
  }

  void _carregarDados() async {
    if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) return;
    setState(() {
      _tempoExecucao = null;
    });
    _cronometro = 0.0;
    _globalConsultaInicio = DateTime.now();
    _startCronometro();
    final stopwatch = Stopwatch()..start();
    bool consultaNecessaria = true;
    // Memoriza filtros atuais – úteis caso usuário navegue para fora e volte enquanto carrega
    _lastEmpresasSelecionadas = List<Empresa>.from(_empresasSelecionadas);
    _lastIntervaloSelecionado = _selectedDateRange;
    // Ativa loaders
    for (final key in _cardLoadStatus.keys) {
      _cardLoadStatus[key] = true;
    }
    if (mounted) setState(() {});

    // Se já houver uma requisição global em andamento, apenas aguarda
    if (_globalFuture != null) {
      _startCronometro();
      // loaders já foram ativados no topo
      await _globalFuture;
      consultaNecessaria = false;
      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
      final chave = '${_empresasSelecionadas.map((e) => e.id).join(",")}|$dias';
      _tempoExecucao = tempoMs / 1000;
      _tempoMedioEstimado = await _tempoRepo.buscarTempoMedio(chave);
      for (final key in _cardLoadStatus.keys) {
        _cardLoadStatus[key] = false;
      }
      if (mounted) {
        _resumo = VendasPageCache.instance.resumo;
        _atualizarValoresFormatados();
        setState(() {});
      }
      return;
    }

    final List<double> tickets = [];
    _globalFuture = () async {
      double totalVenda = 0, lucro = 0, totalVendaBruta = 0, lucroBruto = 0, devolucoes = 0, ticketMedio = 0;
      int nroVendas = 0;

      // === ALTERAÇÃO 21‑06‑2025: removida verificação de _disposed para permitir que a
      // requisição finalize mesmo que a tela seja descartada
      for (final empresa in _empresasSelecionadas) {
        final resultados = await _fatRepo.getResumoFaturamentoComLucro(
          idEmpresa: empresa.id,
          dataInicial: _selectedDateRange!.start,
          dataFinal: _selectedDateRange!.end,
        );
        for (final resultado in resultados) {
          totalVenda += resultado.totalVenda;
          lucro += resultado.lucro;
          totalVendaBruta += resultado.totalVendaBruta;
          lucroBruto += resultado.lucroBruto;
          devolucoes += resultado.devolucoes;
          nroVendas += resultado.nroVendas;
          tickets.add(resultado.ticketMedio);
        }
      }

      ticketMedio = tickets.isNotEmpty
          ? tickets.reduce((a, b) => a + b) / tickets.length
          : 0.0;

      _resumo = FaturamentoComLucro(
        idEmpresa: 0,
        dtMovimento: _selectedDateRange!.start,
        totalVenda: totalVenda,
        lucro: lucro,
        totalVendaBruta: totalVendaBruta,
        lucroBruto: lucroBruto,
        devolucoes: devolucoes,
        nroVendas: nroVendas,
        ticketMedio: ticketMedio,
      );

      _atualizarValoresFormatados();

      for (final key in _cardLoadStatus.keys) {
        _cardLoadStatus[key] = false;
      }

      // Grava cache
      VendasPageCache.instance.salvar(
        resumo: _resumo!,
        empresas: _empresasSelecionadas,
        intervalo: _selectedDateRange!,
      );

      if (mounted) setState(() {});
      // Atualiza memória para o último intervalo concluído
      _lastEmpresasSelecionadas = List<Empresa>.from(_empresasSelecionadas);
      _lastIntervaloSelecionado = _selectedDateRange;

      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
      final chave = '${_empresasSelecionadas.map((e) => e.id).join(",")}|$dias';
      final tempoReal = tempoMs / 1000;
      if (consultaNecessaria) {
        await _tempoRepo.salvarTempo(chave, tempoMs);
      }
      final media = await _tempoRepo.buscarTempoMedio(chave);
      if (mounted) {
        setState(() {
          _tempoExecucao = tempoReal;
          _tempoMedioEstimado = media;
        });
      }
      _cronometroTimer?.cancel();
      _globalConsultaInicio = null;
    }();

    await _globalFuture;
    _globalFuture = null;
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) return;
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${_empresasSelecionadas.map((e) => e.id).join(",")}|$dias';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media = await _tempoRepo.buscarTempoMedio(chave);
    setState(() {
      _tempoExecucao = ultimo;
      _tempoMedioEstimado = media;
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
      if (mounted) {
        setState(() => _selectedDateRange = picked);
      }
      _carregarDados();
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_empresas.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(
                  ignoring: _isLoading,
                  child: Opacity(
                    opacity: _isLoading ? 0.5 : 1.0,
                    child: PopupMenuButton<Empresa>(
                      color: Colors.white,
                      itemBuilder: (context) {
                        return _empresas.map((empresa) {
                          return PopupMenuItem<Empresa>(
                            value: empresa,
                            child: Text(empresa.toString()),
                          );
                        }).toList();
                      },
                      onSelected: (empresa) async {
                        if (mounted) {
                          setState(() {
                            _empresasSelecionadas = empresa.id == 0
                                ? _empresas.where((e) => e.id != 0).toList()
                                : [empresa];
                          });
                        }
                        await _inicializarTempoExecucao();
                        _carregarDados();
                      },
                      tooltip: 'Selecionar empresa',
                      child: TextButton.icon(
                        icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                        label: Text(
                          _empresasSelecionadas.isEmpty
                              ? 'Empresa'
                              : _empresasSelecionadas.length == 1
                              ? _empresasSelecionadas.first.toString()
                              : 'Todas as Empresas',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
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
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _isLoading ? null : _pickDateRange,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_formattedDateRange),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
          children: [
            const TextSpan(
              text: 'Resumo de Vendas',
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
                ),
                // Hide toggle between local/API
              ],
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final cards = [
                {'title': 'Total Venda',   'value': _totalVendaFmt,     'icon': Icons.paid},
                {
                  'title': 'Lucro',
                  'value': _lucroFmt,
                  'secondary': _lucroPercentFmt,
                  'icon': Icons.attach_money
                },
                {'title': 'Venda Bruta',   'value': _totalVendaBrutaFmt,'icon': Icons.trending_up},
                {
                  'title': 'Lucro Bruto',
                  'value': _lucroBrutoFmt,
                  'secondary': _lucroBrutoPercentFmt,
                  'icon': Icons.stacked_line_chart
                },
                {'title': 'Nº Vendas',     'value': _nroVendasFmt,      'icon': Icons.shopping_cart},
                {'title': 'Ticket Médio',  'value': _ticketMedioFmt,    'icon': Icons.calculate},
                {'title': 'Devoluções',    'value': _devolucoesFmt,     'icon': Icons.replay},
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First group: summary
                  GridView.builder(
                    itemCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.0,
                    ),
                    itemBuilder: (context, index) {
                      final data = cards[index];
                      final loading = _cardLoadStatus[index] ?? false;
                      if (loading) {
                        return Container(
                          constraints: const BoxConstraints(minHeight: 100),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0,2))],
                          ),
                          child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth:2))),
                        );
                      }
                      if (index == 0) {
                        return GestureDetector(
                          onTap: () {
                            if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VendasPorDivisaoPage(
                                  empresasSelecionadas: _empresasSelecionadas,
                                  intervalo: _selectedDateRange!,
                                ),
                              ),
                            );
                          },
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              builder: (context) {
                                return SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _NavigationOptionCard(
                                          icon: Icons.view_module,
                                          label: 'Divisão',
                                          onTap: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => VendasPorDivisaoPage(
                                                  empresasSelecionadas: _empresasSelecionadas,
                                                  intervalo: _selectedDateRange!,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _NavigationOptionCard(
                                          icon: Icons.list_alt,
                                          label: 'Seção',
                                          onTap: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => VendasPorSecaoPage(
                                                  empresasSelecionadas: _empresasSelecionadas,
                                                  intervalo: _selectedDateRange!,
                                                  idDivisao: null,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _NavigationOptionCard(
                                          icon: Icons.layers,
                                          label: 'Grupo',
                                          onTap: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => VendasPorGrupoPage(
                                                  empresasSelecionadas: _empresasSelecionadas,
                                                  intervalo: _selectedDateRange!,
                                                  idSecao: null,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        _NavigationOptionCard(
                                          icon: Icons.person,
                                          label: 'Vendedor',
                                          onTap: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => VendasPorVendedorPage(
                                                  empresasSelecionadas: _empresasSelecionadas,
                                                  intervalo: _selectedDateRange!,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          child: _DashboardCard(
                            title: data['title'] as String,
                            value: data['value'].toString(),
                            icon: data['icon'] as IconData,
                            secondary: data['secondary'] as String?,
                          ),
                        );
                      }
                      return _DashboardCard(
                        title: data['title'] as String,
                        value: data['value'].toString(),
                        icon: data['icon'] as IconData,
                        secondary: data['secondary'] as String?,
                      );
                    },
                  ),
                  // const SizedBox(height: 8), // Removido para aproximar Resumo e Métricas
                  // Second group: Indicators
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 10),
                    child: Text(
                      'Métricas',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  GridView.builder(
                    itemCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 2.0,
                    ),
                    itemBuilder: (context, index) {
                      final i = index + 4;
                      final data = cards[i];
                      final loading = _cardLoadStatus[i] ?? false;
                      if (loading) {
                        return Container(
                          constraints: const BoxConstraints(minHeight: 100),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0,2))],
                          ),
                          child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth:2))),
                        );
                      }
                      return _DashboardCard(
                        title: data['title'] as String,
                        value: data['value'].toString(),
                        icon: data['icon'] as IconData,
                        secondary: data['secondary'] as String?,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? secondary;
  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (secondary != null && secondary!.isNotEmpty)
                      Text(
                        secondary!,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



class _NavigationOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavigationOptionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Icon(icon, size: 28, color: Colors.green.shade700),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              )
            ],
          ),
        ),
      ),
    );
  }
}
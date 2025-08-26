import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/repositories/financeiro/contas_pagar_repository.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/services/auth_service.dart';
// === NOVO IMPORT 22-06-2025: cache da página Contas a Pagar
import 'package:analyzepro/services/caches/contas_pagar_page_cache.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import '../../home/menu_principal_page.dart';

class ContasPagarPage extends StatefulWidget {
  const ContasPagarPage({Key? key}) : super(key: key);

  @override
  _ContasPagarPageState createState() => _ContasPagarPageState();
}

class _ContasPagarPageState extends State<ContasPagarPage> with WidgetsBindingObserver {
  // Reuse single AuthService + ApiClient for the whole page.
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final ContasPagarRepository _repository;

  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  DateTimeRange? _selectedDateRange;
  Map<int, bool> _cardLoadStatus = {
    for (int i = 0; i <= 11; i++) i: true,
  };

  // === CONTROLE GLOBAL 26-06-2025 ===
  static Future<void>? _globalFuture;
  // Momento em que a consulta global começou – mantém cronômetro ativo em várias instâncias
  static DateTime? _globalConsultaInicio;
  static final _pageCache = ContasPagarPageCache.instance;

  // Filtros da última busca em andamento
  static Empresa? _lastEmpresaSelecionada;
  static DateTimeRange? _lastIntervaloSelecionado;

  // Indica se algum card está em loading
  bool get _isLoading => _cardLoadStatus.values.any((v) => v == true);
  final Map<String, Map<String, dynamic>> _resumos = {};

  // === FLAGS DE CICLO DE VIDA 22-06-2025 ===

  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoMedioEstimado;

  // === CRONÔMETRO VIVO 29-06-2025 ===
  Timer? _cronometroTimer;
  double _cronometro = 0.0;

  /// Inicia ou reinicia o cronômetro visual baseado em [_globalConsultaInicio].
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsedMs =
          DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() {
        _cronometro = elapsedMs / 1000;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addObserver(this);

    // intervalo padrão = hoje
    final hoje = DateTime.now();
    final hojeInicio = DateTime(hoje.year, hoje.month, hoje.day);
    final hojeFim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);
    _selectedDateRange = DateTimeRange(start: hojeInicio, end: hojeFim);

    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = ContasPagarRepository(_apiClient);

    _carregarEmpresas();
    _tempoRepo = TempoExecucaoRepository();
    _inicializarTempoExecucao();
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresaSelecionada == null || _selectedDateRange == null) return;
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${_empresaSelecionada!.id}|$dias|contas_pagar';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    setState(() {
      _tempoMedioEstimado = media;
    });
  }

  Future<void> _carregarEmpresas() async {
    final service = CadLojasService(_apiClient);
    final empresas = await service.getEmpresasComNome();
    empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    // Se já existe consulta em andamento, aguarda e mantém filtros atuais
    if (_globalFuture != null) {
      for (final k in _cardLoadStatus.keys) _cardLoadStatus[k] = true;
      setState(() {
        _empresas = empresas;
        _empresaSelecionada = _lastEmpresaSelecionada ?? empresas.first;
        _selectedDateRange  = _lastIntervaloSelecionado;
      });
      _startCronometro();
      await _globalFuture;
      for (final k in _cardLoadStatus.keys) _cardLoadStatus[k] = false;
      if (mounted) setState(() {});
      return;
    }
    // === VERIFICA CACHE 22-06-2025 ===
    if (_pageCache.cacheValido) {
      for (final key in _cardLoadStatus.keys) {
        _cardLoadStatus[key] = false;
      }
      if (mounted) {
        setState(() {
          _empresas = empresas;
          _empresaSelecionada = _pageCache.empresaSelecionada;
          _selectedDateRange  = _pageCache.intervaloSelecionado;
          _resumos.clear();
          _resumos.addAll(_pageCache.resumos ?? {});
        });
        // === Adicionado: Atualiza histórico do tempo médio ao restaurar cache ===
        final empresa = _pageCache.empresaSelecionada;
        final intervalo = _pageCache.intervaloSelecionado;
        if (empresa != null && intervalo != null) {
          final dias = intervalo.end.difference(intervalo.start).inDays;
          final chave = '${empresa.id}|$dias|contas_pagar';
          final media = await _tempoRepo.buscarTempoMedio(chave);
          if (mounted) {
            setState(() {
              _tempoMedioEstimado = media;
            });
          }
        }
      }
      return;
    }
    if (mounted) {
      setState(() {
        _empresas = empresas;
        if (_empresas.isNotEmpty) {
          _empresaSelecionada = _empresas.first;
        }
        // Mantém o intervalo atual (já definido no initState) se não vier de cache
      });
    }
    await _carregarDados();
  }

  Future<void> _carregarDados() async {
    if (_selectedDateRange == null) return Future.value();
    setState(() {
    });
    // === INÍCIO CRONÔMETRO VIVO ===
    _cronometro = 0.0;
    _globalConsultaInicio = DateTime.now();
    _startCronometro();
    final stopwatch = Stopwatch()..start();
    bool consultaNecessaria = true;
    // Memoriza filtros atuais
    _lastEmpresaSelecionada   = _empresaSelecionada;
    _lastIntervaloSelecionado = _selectedDateRange;
    final empresasParaBuscar = _empresaSelecionada?.id == 0
        ? _empresas.where((e) => e.id != 0).toList()
        : [_empresaSelecionada!];

    // === loaders no início de _carregarDados() 22-06-2025 ===
    for (int i = 0; i <= 11; i++) {
      _cardLoadStatus[i] = true;
    }
    if (mounted) {
      setState(() {});
    }

    if (_globalFuture != null) {
      _startCronometro();
      await _globalFuture;
      consultaNecessaria = false;
      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
      final chave = '${_empresaSelecionada!.id}|$dias|contas_pagar';
      _tempoMedioEstimado = await _tempoRepo.buscarTempoMedio(chave);
      return;
    }

    _globalFuture = () async {
      try {
        final resumosList = await _repository.getResumoContasPagarMultiplasEmpresas(
          empresasIds: empresasParaBuscar.map((e) => e.id).toList(),
          dataInicial: _selectedDateRange!.start,
          dataFinal: _selectedDateRange!.end,
        );

        _resumos['total'] = {
          'totalAPagar': resumosList.fold(0.0, (s, r) => s + (r.totalAPagar ?? 0.0)),
          'totalPago': resumosList.fold(0.0, (s, r) => s + (r.totalPago ?? 0.0)),
          'saldoAPagar': resumosList.fold(0.0, (s, r) => s + (r.saldoAPagar ?? 0.0)),
          'valorLiquidoPagar': resumosList.fold(0.0, (s, r) => s + (r.valorLiquidoPagar ?? 0.0)),
          'percentualPago': resumosList.isEmpty
              ? 0.0
              : resumosList.fold(0.0, (s, r) => s + (r.percentualPago ?? 0.0)) /
                  resumosList.length,
          'totalJuroMora': resumosList.fold(0.0, (s, r) => s + (r.totalJuroMora ?? 0.0)),
          'totalJuroCobrado': resumosList.fold(0.0, (s, r) => s + (r.totalJuroCobrado ?? 0.0)),
          'totalJuroIsentado': resumosList.fold(0.0, (s, r) => s + (r.totalJuroIsentado ?? 0.0)),
          'totalJuroPostergado':
              resumosList.fold(0.0, (s, r) => s + (r.totalJuroPostergado ?? 0.0)),
          'totalDescontosConcedidos':
              resumosList.fold(0.0, (s, r) => s + (r.totalDescontosConcedidos ?? 0.0)),
          'qtdeTitulosAtrasados':
              resumosList.fold(0, (s, r) => s + (r.qtdeTitulosAtrasados ?? 0)),
          'mediaDiasAtraso': resumosList.isEmpty
              ? 0
              : (resumosList.fold(0, (s, r) => s + (r.mediaDiasAtraso ?? 0)) ~/
                  resumosList.length),
        };

        // Desliga loaders
        for (final k in _cardLoadStatus.keys) _cardLoadStatus[k] = false;

        // Salvar cache se houver valor
        if ((_resumos['total']?['totalAPagar'] ?? 0) > 0) {
          _pageCache.salvar(
            resumos: _resumos,
            empresa: _empresaSelecionada!,
            intervalo: _selectedDateRange!,
          );
        }

        if (mounted) setState(() {});
      } catch (e) {
        for (final k in _cardLoadStatus.keys) _cardLoadStatus[k] = false;
        if (mounted) setState(() {});
      } finally {
        stopwatch.stop();
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        final tempoMs = stopwatch.elapsedMilliseconds;
        final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
        final chave = '${_empresaSelecionada!.id}|$dias|contas_pagar';
        final tempoReal = tempoMs / 1000;
        if (consultaNecessaria) {
          await _tempoRepo.salvarTempo(chave, tempoMs);
        }
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _tempoMedioEstimado = media;
          });
        }
        _globalFuture = null;
      }
    }();

    return _globalFuture!;
  }

  List<Map<String, dynamic>> _cardData() {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final total = _resumos['total'] ?? {};
    return [
      // Resumo
      {
        "title": "Para Pagar",
        "value": currencyFormat.format((total['totalAPagar'] as num?) ?? 0.0),
        "icon": Icons.account_balance_wallet,
      },
      {
        "title": "Total Pago",
        "value": currencyFormat.format((total['totalPago'] as num?) ?? 0.0),
        "icon": Icons.money_off,
      },
      {
        "title": "Saldo a Pagar",
        "value": currencyFormat.format((total['saldoAPagar'] as num?) ?? 0.0),
        "icon": Icons.attach_money,
      },
      {
        "title": "Valor Líquido",
        "value": currencyFormat.format((total['valorLiquidoPagar'] as num?) ?? 0.0),
        "icon": Icons.money_off_csred_outlined,
      },
      {
        "title": "Pago",
        "value": "${((total['percentualPago'] as num?) ?? 0.0).toStringAsFixed(2)}%",
        "icon": Icons.percent,
      },
      // Juros e Descontos
      {
        "title": "Mora",
        "value": currencyFormat.format((total['totalJuroMora'] as num?) ?? 0.0),
        "icon": Icons.warning_amber_rounded,
      },
      {
        "title": "Cobrado",
        "value": currencyFormat.format((total['totalJuroCobrado'] as num?) ?? 0.0),
        "icon": Icons.trending_up,
      },
      {
        "title": "Isentado",
        "value": currencyFormat.format((total['totalJuroIsentado'] as num?) ?? 0.0),
        "icon": Icons.remove_circle,
      },
      {
        "title": "Postergado",
        "value": currencyFormat.format((total['totalJuroPostergado'] as num?) ?? 0.0),
        "icon": Icons.schedule,
      },
      {
        "title": "Descontos",
        "value": currencyFormat.format((total['totalDescontosConcedidos'] as num?) ?? 0.0),
        "icon": Icons.local_offer,
      },
      // Atrasos
      {
        "title": "Em Atraso",
        "value": "${NumberFormat.decimalPattern('pt_BR').format((total['qtdeTitulosAtrasados'] as num?) ?? 0)} títulos",
        "icon": Icons.error_outline,
      },
      {
        "title": "Média Atraso",
        "value": "${NumberFormat.decimalPattern('pt_BR').format((total['mediaDiasAtraso'] as num?) ?? 0)} dias",
        "icon": Icons.timelapse,
      },
    ];
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D32),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Color(0xFF2E7D32),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      await _carregarDados();
    }
  }

  String get _formattedDateRange {
    if (_selectedDateRange == null) return '';
    final f = DateFormat('dd/MM/yyyy');
    return '${f.format(_selectedDateRange!.start)} - ${f.format(_selectedDateRange!.end)}';
  }

  @override
  Widget build(BuildContext context) {
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        itemBuilder: (context) => _empresas
                            .map((empresa) => PopupMenuItem<Empresa>(
                                  value: empresa,
                                  child: Text('${empresa.id} - ${empresa.nome}'),
                                ))
                            .toList(),
                        onSelected: (empresa) {
                          _lastEmpresaSelecionada = empresa;               // memoriza filtro
                          setState(() => _empresaSelecionada = empresa);
                          _carregarDados();
                        },
                        tooltip: 'Selecionar empresa',
                        child: TextButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                          label: Text(
                            _empresaSelecionada != null
                                ? '${_empresaSelecionada!.id} - ${_empresaSelecionada!.nome}'
                                : 'Empresa',
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
                  TextButton.icon(
                    onPressed: _isLoading ? null : _pickDateRange,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _formattedDateRange.isEmpty ? 'Selecione o intervalo' : _formattedDateRange,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Resumo a Pagar Vencidas',
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
                ],
              ),
            Builder(
              builder: (context) {
                final cards = _cardData();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bloco Resumo (0..4)
                    GridView.builder(
                      itemCount: 5,
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
                        return _DashboardCard(
                          title: data['title'],
                          value: data['value'],
                          icon: data['icon'],
                          onTap: null,
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Text(
                        'Juros e Descontos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    GridView.builder(
                      itemCount: 5,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.0,
                      ),
                      itemBuilder: (context, i) {
                        final index = i + 5;
                        final data = cards[index];
                        final loading = _cardLoadStatus[index] ?? false;
                        if (loading) {
                          return Container(
                            constraints: const BoxConstraints(minHeight: 100),
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
                        return _DashboardCard(
                          title: data['title'],
                          value: data['value'],
                          icon: data['icon'],
                          onTap: null,
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Text(
                        'Atrasos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    GridView.builder(
                      itemCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.0,
                      ),
                      itemBuilder: (context, i) {
                        final index = i + 10;
                        final data = cards[index];
                        final loading = _cardLoadStatus[index] ?? false;
                        if (loading) {
                          return Container(
                            constraints: const BoxConstraints(minHeight: 100),
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
                        return _DashboardCard(
                          title: data['title'],
                          value: data['value'],
                          icon: data['icon'],
                          onTap: null,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
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
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _DashboardCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/repositories/financeiro/contas_receber_repository.dart';
import 'package:analyzepro/screens/dashboard/financeiro/contas_receber_vencimento_detalhado_page.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/caches/contas_receber_page_cache.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import '../../../models/financeiro/top_devedor.dart';
import '../../../repositories/financeiro/top_devedores_repository.dart';
import '../../home/menu_principal_page.dart';
import 'contas_receber_por_forma_page.dart';

class ContasReceberPage extends StatefulWidget {
  const ContasReceberPage({super.key});

  @override
  State<ContasReceberPage> createState() => _ContasReceberPageState();
}

// Helper class for aggregated devedor info
class _DevedorResumo {
  final int idclifor;
  final String nome;
  final double totalDevido;
  final int totalTitulos;
  final List<TopDevedor> detalhes;

  _DevedorResumo({
    required this.idclifor,
    required this.nome,
    required this.totalDevido,
    required this.totalTitulos,
    required this.detalhes,
  });
}

class _ContasReceberPageState extends State<ContasReceberPage> with WidgetsBindingObserver {
  // Cronômetro e histórico de Top 10 Devedores
  Timer? _cronometroTimerDevedores;
  double _cronometroDevedores = 0.0;
  static DateTime? _globalDevedoresInicio;
  double? _tempoMedioDevedores;
  // === CACHE DE EMPRESAS ===
  static List<Empresa>? _cachedEmpresas;
  static DateTime? _empresasTimestamp;
  static const int _empresasTtlMin = 30;
  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoMedioEstimado;
  // === CRONÔMETRO VISUAL ===
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  // === CONTROLE GLOBAL 26‑06‑2025 ===
  static Future<void>? _globalFuture;
  // ▶ Top 10 Devedores cache/fetch
  static Future<void>? _topDevedoresFuture;
  static List<_DevedorResumo>? _cachedTopDevedores;
  static DateTime? _devedoresTimestamp;
  static const int _devedoresTtlMin = 30;
  // Marca o início da consulta global para manter o cronômetro ativo
  static DateTime? _globalConsultaInicio;
  // Alias para o cache da página
  static final _pageCache = ContasReceberPageCache.instance;
  /// Inicia ou reinicia o cronômetro visual baseado em [_globalConsultaInicio].
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsed = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() => _cronometro = elapsed / 1000);
    });
  }

  /// Inicia ou reinicia o cronômetro visual dos Top 10 Devedores.
  void _startCronometroDevedores() {
    if (_globalDevedoresInicio == null) return;
    _cronometroTimerDevedores?.cancel();
    _cronometroTimerDevedores = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalDevedoresInicio == null) return;
      final elapsed = DateTime.now().difference(_globalDevedoresInicio!).inMilliseconds;
      setState(() => _cronometroDevedores = elapsed / 1000);
    });
  }
  // === ALTERAÇÃO 22‑06‑2025: garante remoção do observer
  @override
  void dispose() {
    _cronometroTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // === ALTERAÇÃO 22‑06‑2025: recarrega dados quando o app volta ao foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cronometroTimer?.cancel();
      _cronometroTimerDevedores?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // Retoma o cronômetro geral se houver consulta em andamento
      if (_globalConsultaInicio != null) {
        _startCronometro();
      }
      // Retoma o cronômetro dos devedores se houver consulta em andamento
      if (_globalDevedoresInicio != null) {
        _startCronometroDevedores();
      }
    }
  }
  // Reuse a single AuthService/ApiClient across the whole page to avoid
  // múltiplas autenticações redundantes.
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final ContasReceberRepository _repository;
  List<_DevedorResumo> _topDevedoresResumo = [];
  bool _carregandoDevedores = false;


  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;

  DateTimeRange? _selectedDateRange;
  // Atualize o _cardLoadStatus para incluir índices de 0 a 11 (12 cards)
  Map<int, bool> _cardLoadStatus = {
    0: true,
    1: true,
    2: true,
    3: true,
    4: true,
    5: true,
    6: true,
    7: true,
    8: true,
    9: true,
    10: true,
    11: true,
  };
  // Filtros da última busca em andamento / concluída
  static Empresa? _lastEmpresaSelecionada;
  static DateTimeRange? _lastIntervaloSelecionado;

  // Loader geral para bloquear UI
  bool get _isLoading => _cardLoadStatus.values.any((v) => v == true);
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');

  final Map<String, Map<String, dynamic>> _resumos = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = ContasReceberRepository(_apiClient);
    _tempoRepo = TempoExecucaoRepository();
    _carregarEmpresas();
    _inicializarTempoExecucao();
    _inicializarTempoExecucaoDevedores();
    // Se já temos cache recente, usa sem recarregar
    if (_cachedTopDevedores != null &&
        _devedoresTimestamp != null &&
        DateTime.now().difference(_devedoresTimestamp!).inMinutes < _devedoresTtlMin) {
      _topDevedoresResumo = _cachedTopDevedores!;
      _carregandoDevedores = false;
    }
    // Se uma requisição está em andamento, aguarda e atualiza estado ao completar
    else if (_topDevedoresFuture != null) {
      _carregandoDevedores = true;
      // Retoma o cronômetro de devedores se a consulta ainda estiver em andamento
      _startCronometroDevedores();
      _topDevedoresFuture!.then((_) {
        if (mounted) {
          setState(() {
            _topDevedoresResumo = _cachedTopDevedores ?? [];
            _carregandoDevedores = false;
          });
        }
      });
    }
  }

  Future<void> _inicializarTempoExecucaoDevedores() async {
    if (_empresaSelecionada == null) return;
    final chave = '${_empresaSelecionada!.id}|top_devedores';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    setState(() {
      _tempoMedioDevedores = media;
    });
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresaSelecionada == null || _selectedDateRange == null) return;
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${_empresaSelecionada!.id}|$dias|contas_receber';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    setState(() {
      _tempoMedioEstimado = media;
    });
  }

  Future<void> _carregarEmpresas() async {
    final service = CadLojasService(_apiClient);
    // ===== CACHE DE EMPRESAS (30 min) =====
    final bool cacheOk = _cachedEmpresas != null &&
        _empresasTimestamp != null &&
        DateTime.now().difference(_empresasTimestamp!).inMinutes < _empresasTtlMin;

    final empresas = cacheOk
        ? List<Empresa>.from(_cachedEmpresas!)
        : await service.getEmpresasComNome();

    if (!cacheOk) {
      _cachedEmpresas = List<Empresa>.from(empresas);
      _empresasTimestamp = DateTime.now();
    }

    if (empresas.isNotEmpty && empresas.first.id != 0) {
      empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }

    // Se há requisição global em andamento, mostra loaders e aguarda
    if (_globalFuture != null) {
      for (final k in _cardLoadStatus.keys) _cardLoadStatus[k] = true;
      _startCronometro();
      setState(() {
        _empresas = empresas;
        _empresaSelecionada = _lastEmpresaSelecionada ?? empresas.first;
        _selectedDateRange  = _lastIntervaloSelecionado;
      });
      await _globalFuture;
      for (final k in _cardLoadStatus.keys) _cardLoadStatus[k] = false;
      if (mounted) setState(() {});
      return;
    }
    // === VERIFICA CACHE 22‑06‑2025 ===
    if (_pageCache.cacheValido) {
      // Desativa loaders
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
      }
      // Adiciona: garantir exibição do tempo médio mesmo ao usar cache
      final empresa = _pageCache.empresaSelecionada;
      final intervalo = _pageCache.intervaloSelecionado;
      if (empresa != null && intervalo != null) {
        final dias = intervalo.end.difference(intervalo.start).inDays;
        final chave = '${empresa.id}|$dias|contas_receber';
        final tempo = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _tempoMedioEstimado = tempo;
          });
        }
      }
      return;
    }
    final hoje = DateTime.now();
    final hojeInicio = DateTime(hoje.year, hoje.month, hoje.day);
    final hojeFim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);

    setState(() {
      _empresas = empresas;
      _empresaSelecionada = empresas.length > 1 ? empresas[1] : (empresas.isNotEmpty ? empresas.first : null);
      _selectedDateRange = DateTimeRange(start: hojeInicio, end: hojeFim);
    });

    if (_empresaSelecionada != null && _selectedDateRange != null) {
      // Exibe tempo médio imediatamente antes do carregamento iniciar
      final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
      final chave = '${_empresaSelecionada!.id}|$dias|contas_receber';
      final tempo = await _tempoRepo.buscarTempoMedio(chave);
      if (mounted) {
        setState(() {
          _tempoMedioEstimado = tempo;
        });
      }
      // Inicializa histórico de tempo dos Devedores
      await _inicializarTempoExecucaoDevedores();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carregarDados(); // Top 10 Devedores será carregado apenas via botão
      });
    }
  }

  /// Carrega o Top 10 Devedores de forma agregada por devedor, respeitando empresa selecionada.
  Future<void> _carregarTopDevedores() async {
    // Inicia cronômetro visual para devedores
    _cronometroDevedores = 0.0;
    _globalDevedoresInicio = DateTime.now();
    _cronometroTimerDevedores?.cancel();
    _cronometroTimerDevedores = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalDevedoresInicio == null) return;
      final elapsed = DateTime.now().difference(_globalDevedoresInicio!).inMilliseconds;
      setState(() => _cronometroDevedores = elapsed / 1000);
    });
    final stopwatchDevedores = Stopwatch()..start();
    // Se cache válido, não recarrega
    if (_cachedTopDevedores != null &&
        _devedoresTimestamp != null &&
        DateTime.now().difference(_devedoresTimestamp!).inMinutes < _devedoresTtlMin) {
      _cronometroTimerDevedores?.cancel();
      _globalDevedoresInicio = null;
      return;
    }
    // Se já está carregando, apenas aguarda
    if (_topDevedoresFuture != null) {
      _cronometroTimerDevedores?.cancel();
      _globalDevedoresInicio = null;
      return _topDevedoresFuture;
    }
    _topDevedoresFuture = () async {
      if (_empresaSelecionada == null) return;
      setState(() {
        _carregandoDevedores = true;
        _topDevedoresResumo.clear();
      });

      // Apenas a(s) empresa(s) atualmente filtrada(s)
      final empresasAlvo = _empresaSelecionada!.id == 0
          ? _empresas.where((e) => e.id != 0).toList()
          : [_empresaSelecionada!];

      final empresasOrdenadas = empresasAlvo..sort((a, b) => a.id.compareTo(b.id));
      final topRepo = TopDevedoresRepository(_apiClient);

      try {
        // busca paralela
        final listas = await Future.wait(
          empresasOrdenadas.map(
                (e) => topRepo.fetchTopDevedores(idEmpresa: e.id)
                .catchError((_) => <TopDevedor>[]),
          ),
        );

        // agrupa por devedor
        final Map<int, List<TopDevedor>> porDevedor = {};
        for (final lista in listas) {
          for (final d in lista) {
            porDevedor.putIfAbsent(d.idclifor, () => []).add(d);
          }
        }

        final agregados = porDevedor.values.map((lista) {
          final total = lista.fold<double>(
              0.0, (s, d) => s + (d.valordevido ?? 0.0));
          final qtdT = lista.fold<int>(0, (s, d) => s + (d.qtdtitulos ?? 0));
          final primeiro = lista.first;
          return _DevedorResumo(
            idclifor: primeiro.idclifor,
            nome: primeiro.nome,
            totalDevido: total,
            totalTitulos: qtdT,
            detalhes: lista,
          );
        }).toList()
          ..sort((a, b) => b.totalDevido.compareTo(a.totalDevido));

        _topDevedoresResumo = agregados.take(10).toList();
        // Ao final, antes de setState:
        _cachedTopDevedores = _topDevedoresResumo;
        _devedoresTimestamp = DateTime.now();
        // Registra tempo no repositório
        final tempoMs = stopwatchDevedores.elapsedMilliseconds;
        final chave = '${_empresaSelecionada!.id}|top_devedores';
        await _tempoRepo.salvarTempo(chave, tempoMs);
        final media = await _tempoRepo.buscarTempoMedio(chave);
        _cronometroTimerDevedores?.cancel();
        _globalDevedoresInicio = null;
        setState(() {
          _tempoMedioDevedores = media;
        });
        if (mounted) {
          setState(() {
            _carregandoDevedores = false;
          });
        }
      } catch (_) {
        _cronometroTimerDevedores?.cancel();
        _globalDevedoresInicio = null;
        if (mounted) {
          setState(() {
            _carregandoDevedores = false;
          });
        }
      }
    }();
    return _topDevedoresFuture!;
  }

  void _mostrarDetalhesDevedor(_DevedorResumo dev) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dev.nome,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...dev.detalhes.map((d) {
                        final empresa =
                            _empresas.firstWhere((e) => e.id == d.idempresa);
                        return ListTile(
                          title: Text(empresa.toString()),
                          trailing: Text(
                            NumberFormat.currency(
                                    locale: 'pt_BR', symbol: 'R\$')
                                .format(d.valordevido),
                          ),
                        );
                      }).toList(),
                      const Divider(),
                      ListTile(
                        title: const Text('Total'),
                        trailing: Text(
                          NumberFormat.currency(
                                  locale: 'pt_BR', symbol: 'R\$')
                              .format(dev.totalDevido),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _carregarDados() async {
    if (_empresaSelecionada == null || _selectedDateRange == null) return Future.value();
    setState(() {
    });
    // === INÍCIO CRONÔMETRO VISUAL ===
    _cronometro = 0.0;
    _globalConsultaInicio = DateTime.now();
    _startCronometro();
    final stopwatch = Stopwatch()..start();
    bool consultaNecessaria = true;
    // Salva filtros atuais para restauração caso usuário volte antes da conclusão
    _lastEmpresaSelecionada = _empresaSelecionada;
    _lastIntervaloSelecionado = _selectedDateRange;
    final dataInicial = _selectedDateRange!.start;
    final dataFinal = _selectedDateRange!.end;

    // === ALTERAÇÃO 22‑06‑2025: Atualiza loaders no início de _carregarDados()
    for (int i = 0; i <= 11; i++) {
      _cardLoadStatus[i] = true;
    }
    if (mounted) {
      setState(() {});
    }

    final empresasSelecionadas = _empresaSelecionada!.id == 0
        ? _empresas.where((e) => e.id != 0).toList()
        : [_empresaSelecionada!];

    final idsEmpresas = empresasSelecionadas.map((e) => e.id).toList();

    // Se já existe requisição global em andamento, apenas aguarda
    if (_globalFuture != null) {
      consultaNecessaria = false;
      stopwatch.stop();
      final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
      final chave = '${_empresaSelecionada!.id}|$dias|contas_receber';
      _tempoMedioEstimado = await _tempoRepo.buscarTempoMedio(chave);
      _startCronometro();
      await _globalFuture;
      _cronometroTimer?.cancel();
      return;
    }

    _globalFuture = () async {
      try {
        final resumosList = await _repository.getResumoContasReceberMultiplasEmpresas(
          empresasIds: idsEmpresas,
          dataInicial: dataInicial,
          dataFinal: dataFinal,
        );

        _resumos['total'] = {
          'totalAReceber': resumosList.fold(0.0, (sum, r) => sum + (r.totalAReceber ?? 0.0)),
          'totalPago': resumosList.fold(0.0, (sum, r) => sum + (r.totalPago ?? 0.0)),
          'saldoAReceber': resumosList.fold(0.0, (sum, r) => sum + (r.saldoAReceber ?? 0.0)),
          'valorLiquidoReceber': resumosList.fold(0.0, (sum, r) => sum + (r.valorLiquidoReceber ?? 0.0)),
          'percentualRecebido': resumosList.isEmpty
              ? 0.0
              : resumosList.fold(0.0, (sum, r) => sum + (r.percentualRecebido ?? 0.0)) / resumosList.length,
          'totalJuroMora': resumosList.fold(0.0, (sum, r) => sum + (r.totalJuroMora ?? 0.0)),
          'totalJuroCobrado': resumosList.fold(0.0, (sum, r) => sum + (r.totalJuroCobrado ?? 0.0)),
          'totalJuroIsentado': resumosList.fold(0.0, (sum, r) => sum + (r.totalJuroIsentado ?? 0.0)),
          'totalJuroPostergado': resumosList.fold(0.0, (sum, r) => sum + (r.totalJuroPostergado ?? 0.0)),
          'totalDescontosConcedidos': resumosList.fold(0.0, (sum, r) => sum + (r.totalDescontosConcedidos ?? 0.0)),
          'qtdeTitulosAtrasados': resumosList.fold(0, (sum, r) => sum + (r.qtdeTitulosAtrasados ?? 0)),
          'mediaDiasAtraso': resumosList.isEmpty
              ? 0
              : (resumosList.fold(0, (sum, r) => sum + (r.mediaDiasAtraso ?? 0)) ~/ resumosList.length),
        };

        // Desliga loaders
        for (int i = 0; i <= 11; i++) _cardLoadStatus[i] = false;

        // Salva no cache se houver dados
        if ((_resumos['total']?['totalAReceber'] ?? 0) > 0) {
          _pageCache.salvar(
            resumos: _resumos,
            empresa: _empresaSelecionada!,
            intervalo: _selectedDateRange!,
          );
        }

        if (mounted) setState(() {});
      } catch (e) {
        for (int i = 0; i <= 11; i++) _cardLoadStatus[i] = false;
        if (mounted) setState(() {});
      } finally {
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        stopwatch.stop();
        final tempoMs = stopwatch.elapsedMilliseconds;
        final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
        final chave = '${_empresaSelecionada!.id}|$dias|contas_receber';
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

    await _globalFuture;
  }


  List<Map<String, dynamic>> _cardData(BuildContext context) {
    final List<Map<String, dynamic>> cards = [];
    cards.add({
      "title": "Para Receber",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalAReceber']) as num?) ?? 0.0)}",
      "icon": Icons.account_balance_wallet,
      "onTap": () {
        if (_empresaSelecionada != null && _selectedDateRange != null) {
          final empresasSelecionadas = _empresaSelecionada!.id == 0
              ? _empresas.where((e) => e.id != 0).toList()
              : [_empresaSelecionada!];

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ContasReceberVencimentoDetalhadoPage(
                empresasSelecionadas: empresasSelecionadas,
                intervalo: _selectedDateRange!,
              ),
            ),
          );
        }
      },
      "onLongPress": () {
        if (_empresaSelecionada == null || _selectedDateRange == null) return;
        final empresasSelecionadas = _empresaSelecionada!.id == 0
            ? _empresas.where((e) => e.id != 0).toList()
            : [_empresaSelecionada!];

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
                      icon: Icons.credit_card,
                      label: 'Por Forma de Pgto',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContasReceberPorFormaPage(
                              empresasSelecionadas: empresasSelecionadas,
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
    });
    cards.add({
      "title": "Total Recebido",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalPago']) as num?) ?? 0.0)}",
      "icon": Icons.payments_outlined,
    });
    cards.add({
      "title": "Saldo Receber",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['saldoAReceber']) as num?) ?? 0.0)}",
      "icon": Icons.attach_money,
    });
    cards.add({
      "title": "Valor Líquido",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['valorLiquidoReceber']) as num?) ?? 0.0)}",
      "icon": Icons.money_off_csred_outlined,
    });
    cards.add({
      "title": "Recebido",
      "value": "${(((_resumos['total']?['percentualRecebido']) as num?) ?? 0.0).toStringAsFixed(2)}%",
      "icon": Icons.percent,
    });
    cards.add({
      "title": "Juro Mora",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalJuroMora']) as num?) ?? 0.0)}",
      "icon": Icons.warning_amber_rounded,
    });
    cards.add({
      "title": "Juro Cobrado",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalJuroCobrado']) as num?) ?? 0.0)}",
      "icon": Icons.trending_up,
    });
    cards.add({
      "title": "Juro Isentado",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalJuroIsentado']) as num?) ?? 0.0)}",
      "icon": Icons.remove_circle,
    });
    cards.add({
      "title": "Juro Postergado",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalJuroPostergado']) as num?) ?? 0.0)}",
      "icon": Icons.schedule,
    });
    cards.add({
      "title": "Descontos",
      "value": "${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(((_resumos['total']?['totalDescontosConcedidos']) as num?) ?? 0.0)}",
      "icon": Icons.local_offer,
    });
    final atrasados = ((_resumos['total']?['qtdeTitulosAtrasados']) as num?) ?? 0;
    cards.add({
      "title": "Atrasados",
      "value": "${NumberFormat.decimalPattern('pt_BR').format(atrasados)} títulos",
      "icon": Icons.error_outline,
    });
    final mediaDias = ((_resumos['total']?['mediaDiasAtraso']) as num?) ?? 0;
    cards.add({
      "title": "Atraso Médio",
      "value": "${NumberFormat.decimalPattern('pt_BR').format(mediaDias)} dias",
      "icon": Icons.timelapse,
    });
    return cards;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(2000);
    final lastDate = DateTime(2100);
    final initialDateRange = _selectedDateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
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

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _carregarDados();
    }
  }

  String get _formattedDateRange {
    if (_selectedDateRange == null) return 'Selecione o intervalo';
    final start = _formatter.format(_selectedDateRange!.start);
    final end = _formatter.format(_selectedDateRange!.end);
    return '$start - $end';
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
        actions: const [
        ],
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
                        itemBuilder: (context) {
                          return _empresas.map((empresa) {
                            return PopupMenuItem<Empresa>(
                              value: empresa,
                              child: Text(empresa.toString()),
                            );
                          }).toList();
                        },
                        onSelected: (empresa) async {
                          _lastEmpresaSelecionada = empresa;
                          setState(() {
                            _empresaSelecionada = empresa;
                          });
                          await _inicializarTempoExecucao();
                          _carregarDados();
                        },
                        tooltip: 'Selecionar empresa',
                        child: TextButton.icon(
                          icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                          label: Text(
                            _empresaSelecionada?.toString() ?? 'Empresa',
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
                    label: Text(
                      _formattedDateRange,
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
                  // Removido o Row com Checkbox de seleção de dados locais.
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Resumo a Receber Vencidas',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: '  ${_cronometro.toStringAsFixed(1)}s',
                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                              if (_tempoMedioEstimado != null)
                                TextSpan(
                                  text: ' (~${_tempoMedioEstimado!.toStringAsFixed(1)}s)',
                                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            Builder(
              builder: (context) {
                final cards = _cardData(context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Resumo a Receber Vencidas (indices 0..4)
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
                      itemBuilder: (ctx, i) {
                        final data = cards[i];
                        final loading = _cardLoadStatus[i] ?? false;
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
                          onTap: data['onTap'],
                          onLongPress: data['onLongPress'],
                        );
                      },
                    ),

                    // Section 3: Juros e Descontos (indices 5..9)
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
                      itemBuilder: (ctx, i) {
                        final data = cards[5 + i];
                        final loading = _cardLoadStatus[5 + i] ?? false;
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
                          onTap: data['onTap'],
                          onLongPress: data['onLongPress'],
                        );
                      },
                    ),
                    // Section 4: Atrasos (indices 10..11)
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
                      itemBuilder: (ctx, i) {
                        final data = cards[10 + i];
                        final loading = _cardLoadStatus[10 + i] ?? false;
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
                          onTap: data['onTap'],
                          onLongPress: data['onLongPress'],
                        );
                      },
                    ),
                    // Top 10 Devedores Section
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Top 10 Devedores',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: '  ${_cronometroDevedores.toStringAsFixed(1)}s',
                                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                                if (_tempoMedioDevedores != null)
                                  TextSpan(
                                    text: ' (~${_tempoMedioDevedores!.toStringAsFixed(1)}s)',
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _carregarTopDevedores,
                          style: TextButton.styleFrom(foregroundColor: Colors.blue),
                          child: const Text('Carregar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_carregandoDevedores && _topDevedoresResumo.isEmpty)
                      const Center(child: CircularProgressIndicator())
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _topDevedoresResumo.map((dev) {
                          return InkWell(
                            onTap: () => _mostrarDetalhesDevedor(dev),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 4)
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(dev.nome,
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                                        .format(dev.totalDevido),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2E7D32)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Títulos: ${dev.totalTitulos}',
                                      style: const TextStyle(color: Colors.black54)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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
}


// Classe _DashboardCard agora local, movida para dentro do arquivo.
class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DashboardCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
// === ALTERAÇÃO 22‑06‑2025: garante remoção do observer
// Lifecycle methods moved into _ContasReceberPageState
// Card de navegação padrão para opções do BottomSheet
class _NavigationOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _NavigationOptionCard({
    Key? key,
    required this.icon,
    required this.label,
    this.onTap,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2E7D32)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        onTap: onTap,
      ),
    );
  }
}
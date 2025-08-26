import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/models/financeiro/inadimplencia.dart';
import 'package:analyzepro/repositories/financeiro/inadimplencia_repository.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/caches/inadimplencia_cache.dart';
import '../../home/menu_principal_page.dart';

class InadimplenciaPage extends StatefulWidget {
  const InadimplenciaPage({super.key});

  @override
  State<InadimplenciaPage> createState() => _InadimplenciaPageState();
}

class _InadimplenciaPageState extends State<InadimplenciaPage> with WidgetsBindingObserver {
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  // Marca o início da consulta global para manter o cronômetro ativo
  static DateTime? _globalConsultaInicio;

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
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final InadimplenciaRepository _repository;
  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoMedioEstimado; // tempo médio histórico

  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  String? _mesSelecionado;
  bool _usarHojeComoFinal = false;
  bool _isLoading = false;

  final _cache = InadimplenciaCache.instance;

  List<Inadimplencia> _dados = [];

  final List<String> _mesesDisponiveis = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = InadimplenciaRepository(_apiClient);
    _tempoRepo = TempoExecucaoRepository();
    _carregarEmpresas();
  }

  Future<void> inicializarTempoExecucao() async {
    if (_empresaSelecionada == null || _mesSelecionado == null) return;
    final dias = _dtFim.difference(_dtInicio).inDays;
    final chave = '${_empresaSelecionada!.id}|$dias';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    setState(() {
      _tempoMedioEstimado = media;
    });
  }

  Future<void> _carregarEmpresas() async {
    List<Empresa> empresas;
    if (_cache.empresasValidas) {
      empresas = List<Empresa>.from(_cache.cachedEmpresas!);
    } else {
      final service = CadLojasService(_apiClient);
      empresas = await service.getEmpresasComNome();
      _cache.setEmpresas(empresas);
    }
    if (empresas.isEmpty || empresas.first.id != 0) {
      empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }
    final hoje = DateTime.now();
    final mesAno = DateFormat('MM/yyyy').format(hoje);
    _gerarMesesDisponiveis();
    setState(() {
      _empresas = empresas;
      _empresaSelecionada = _cache.lastEmpresa ?? (empresas.length > 1 ? empresas[1] : empresas.first);
      _mesSelecionado = _cache.lastMes ?? mesAno;
      _usarHojeComoFinal = _cache.lastHojeFinal ??
          (_mesSelecionado == mesAno); // ligado se mês atual
    });
    await inicializarTempoExecucao();
    _carregarDados();
  }

  void _gerarMesesDisponiveis() {
    final now = DateTime.now();
    _mesesDisponiveis.clear();
    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      _mesesDisponiveis.add(DateFormat('MM/yyyy').format(date));
    }
  }

  DateTime get _dtInicio {
    final parts = _mesSelecionado!.split('/');
    final month = int.parse(parts[0]);
    final year = int.parse(parts[1]);
    return DateTime(year, month, 1);
  }

  DateTime get _dtFim {
    if (_usarHojeComoFinal &&
        _mesInt == DateTime.now().month &&
        _anoInt == DateTime.now().year) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, 23, 59, 59);
    }
    final start = _dtInicio;
    final nextMonth = (start.month < 12)
        ? DateTime(start.year, start.month + 1, 1)
        : DateTime(start.year + 1, 1, 1);
    return nextMonth.subtract(const Duration(seconds: 1));
  }

  int get _mesInt => int.parse(_mesSelecionado!.split('/')[0]);
  int get _anoInt => int.parse(_mesSelecionado!.split('/')[1]);

  Future<void> _carregarDados() async {
    // Verifica se dados do cache serão usados antes de iniciar cronômetro
    final isCacheValido = _cache.resultadoValido(_empresaSelecionada!, _mesSelecionado!, _usarHojeComoFinal);

    if (!isCacheValido) {
      // Só reinicia cronômetro se ainda não existe consulta em andamento.
      if (_globalConsultaInicio == null) {
        _cronometro = 0.0;
        _globalConsultaInicio = DateTime.now();
      }
      _startCronometro(); // Garante que novas instâncias usem o cronômetro atual
    }
    if (_empresaSelecionada == null || _mesSelecionado == null) return;
    setState(() => _isLoading = true);
    bool consultaNecessaria = true;

    // salva filtros
    _cache.lastEmpresa = _empresaSelecionada;
    _cache.lastMes = _mesSelecionado;
    _cache.lastHojeFinal = _usarHojeComoFinal;

    final stopwatch = Stopwatch()..start();

    // Usa resultado cache se válido
    if (_cache.resultadoValido(_empresaSelecionada!, _mesSelecionado!, _usarHojeComoFinal)) {
      setState(() {
        _dados = [
          _cache.cachedResumo ??
              Inadimplencia(
                idEmpresa: _empresaSelecionada?.id ?? 0,
                mes: _mesInt,
                ano: _anoInt,
                valTitulos: 0,
                valDescConcedido: 0,
                valPagoEmDia: 0,
                valPagoInadimp: 0,
                valInadimpAtual: 0,
                valInadimpMes: 0,
                valPendente: 0,
                valPerda: 0,
              )
        ];
        _isLoading = false;
      });
      consultaNecessaria = false;
      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final dias = _dtFim.difference(_dtInicio).inDays;
      final chave = '${_empresaSelecionada?.id}|$dias';
      final media = await _tempoRepo.buscarTempoMedio(chave);
      if (mounted) {
        setState(() {
          _tempoMedioEstimado = media;
        });
      }
      // Removido: await _tempoRepo.salvarTempo(chave, tempoMs);
      return;
    }

    // evita requisição duplicada
    if (_cache.globalFetching && _cache.globalFuture != null) {
      await _cache.globalFuture!;
      _startCronometro();
      setState(() {
        _dados = [
          _cache.cachedResumo ??
              Inadimplencia(
                idEmpresa: _empresaSelecionada?.id ?? 0,
                mes: _mesInt,
                ano: _anoInt,
                valTitulos: 0,
                valDescConcedido: 0,
                valPagoEmDia: 0,
                valPagoInadimp: 0,
                valInadimpAtual: 0,
                valInadimpMes: 0,
                valPendente: 0,
                valPerda: 0,
              )
        ];
        _isLoading = false;
      });
      consultaNecessaria = false;
      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final dias = _dtFim.difference(_dtInicio).inDays;
      final chave = '${_empresaSelecionada?.id}|$dias';
      final media = await _tempoRepo.buscarTempoMedio(chave);
      if (mounted) {
        setState(() {
          _tempoMedioEstimado = media;
        });
      }
      // Removido: await _tempoRepo.salvarTempo(chave, tempoMs);
      return;
    }
    _cache.globalFetching = true;

    _cache.globalFuture = () async {
      try {
        final empresasSelecionadas = _empresaSelecionada!.id == 0
            ? _empresas.where((e) => e.id != 0).toList()
            : [_empresaSelecionada!];

        final idsEmpresas = empresasSelecionadas.map((e) => e.id).toList();
        final res = await _repository.getResumoInadimplenciaMultiplasEmpresas(
          empresasIds: idsEmpresas,
          dataInicial: _dtInicio,
          dataFinal: _dtFim,
        );
        final resumo = res.isNotEmpty
            ? res.first
            : Inadimplencia(
                idEmpresa: _empresaSelecionada!.id,
                mes: _mesInt,
                ano: _anoInt,
                valTitulos: 0,
                valDescConcedido: 0,
                valPagoEmDia: 0,
                valPagoInadimp: 0,
                valInadimpAtual: 0,
                valInadimpMes: 0,
                valPendente: 0,
                valPerda: 0,
              );

        _cache.setResultado(
          resumo: resumo,
          empresa: _empresaSelecionada!,
          mes: _mesSelecionado!,
          hojeFinal: _usarHojeComoFinal,
        );
        setState(() => _dados = [resumo]);
        stopwatch.stop();
        final tempoMs = stopwatch.elapsedMilliseconds;
        final dias = _dtFim.difference(_dtInicio).inDays;
        final chave = '${_empresaSelecionada?.id}|$dias';
        if (consultaNecessaria) {
          await _tempoRepo.salvarTempo(chave, tempoMs);
        }
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _tempoMedioEstimado = media;
          });
        }
      } catch (_) {
        setState(() => _dados = []);
      } finally {
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        _cache.globalFetching = false;
        _cache.globalFuture = null;
        setState(() => _isLoading = false);
      }
    }();

    await _cache.globalFuture!;
  }

  Map<String, String> _formatValues(Inadimplencia? ina) {
    if (_isLoading || ina == null) {
      return {
        "inadAtual":        '...',
        "inadMes":          '...',
        "pendente":         '...',
        "perda":            '...',
        "titulos":          '...',
        "desconto":         '...',
        "pagoEmDia":        '...',
        "pagoInadimp":      '...',
      };
    }

    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return {
      "inadAtual":        f.format(ina.valInadimpAtual),
      "inadMes":          f.format(ina.valInadimpMes),
      "pendente":         f.format(ina.valPendente),
      "perda":            f.format(ina.valPerda),
      "titulos":          f.format(ina.valTitulos),
      "desconto":         f.format(ina.valDescConcedido),
      "pagoEmDia":        f.format(ina.valPagoEmDia),
      "pagoInadimp":      f.format(ina.valPagoInadimp),
    };
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

  @override
  Widget build(BuildContext context) {
    final ina = _dados.isNotEmpty ? _dados.first : null;
    final vals = _formatValues(ina);

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
                      opacity: _isLoading ? 0.5 : 1,
                      child: PopupMenuButton<Empresa>(
                        itemBuilder: (ctx) => _empresas.map((e) => PopupMenuItem(
                          value: e,
                          child: Text(e.toString()),
                        )).toList(),
                        onSelected: (empresa) async {
                          setState(() => _empresaSelecionada = empresa);
                          await inicializarTempoExecucao();
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  IgnorePointer(
                    ignoring: _isLoading,
                    child: Opacity(
                      opacity: _isLoading ? 0.5 : 1,
                      child: PopupMenuButton<String>(
                        initialValue: _mesSelecionado,
                        itemBuilder: (context) {
                          return _mesesDisponiveis.map((mes) {
                            return PopupMenuItem<String>(
                              value: mes,
                              child: Text(mes),
                            );
                          }).toList();
                        },
                        onSelected: (mes) async {
                          setState(() {
                            _mesSelecionado = mes;
                            _usarHojeComoFinal = false; // reseta
                          });
                          await inicializarTempoExecucao();
                          _carregarDados();
                        },
                        child: TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18, color: Colors.black87),
                          label: Text(
                            _mesSelecionado ?? 'Mês/Ano',
                            style: const TextStyle(color: Colors.black87),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Switch "Hoje como data final?"
                  if (_mesInt == DateTime.now().month &&
                      _anoInt == DateTime.now().year)
                    IgnorePointer(
                      ignoring: _isLoading,
                      child: Opacity(
                        opacity: _isLoading ? 0.5 : 1,
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: null,
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              child: const Text('Hoje como data final?', style: TextStyle(color: Colors.black87)),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: _usarHojeComoFinal,
                              onChanged: _isLoading
                                  ? null
                                  : (v) async {
                                      setState(() => _usarHojeComoFinal = v);
                                      await inicializarTempoExecucao();
                                      _carregarDados();
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            // --- Seção 1: Resumo de Inadimplência -----------------------
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Resumo de Inadimplência',
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
            ),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.0,
              ),
              children: [
                _DashboardCard(title: 'Atualmente', value: vals['inadAtual']!, icon: Icons.warning_amber, isLoading: _isLoading),
                _DashboardCard(title: 'Nesse Mês', value: vals['inadMes']!, icon: Icons.calendar_month, isLoading: _isLoading),
              ],
            ),

            // --- Seção 2: Pagamentos & Recebimentos ---------------------
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Pagamentos & Recebimentos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.0,
              ),
              children: [
                _DashboardCard(title: 'Valor Total', value: vals['titulos']!, icon: Icons.receipt_long, isLoading: _isLoading),
                _DashboardCard(title: 'Desc. Cedidos', value: vals['desconto']!, icon: Icons.percent, isLoading: _isLoading),
                _DashboardCard(title: 'Pago em Dia', value: vals['pagoEmDia']!, icon: Icons.check_circle_outline, isLoading: _isLoading),
                _DashboardCard(title: 'Pago Inadimp.', value: vals['pagoInadimp']!, icon: Icons.payment, isLoading: _isLoading),
              ],
            ),

            // --- Seção 3: Pendências & Perdas ---------------------------
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Pendências & Perdas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.0,
              ),
              children: [
                _DashboardCard(title: 'Pendente', value: vals['pendente']!, icon: Icons.timelapse, isLoading: _isLoading),
                _DashboardCard(title: 'Perdido',    value: vals['perda']!,    icon: Icons.cancel, isLoading: _isLoading),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool isLoading;

  const _DashboardCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/repositories/compras/diferenca_pedido_nota_repository.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import 'package:analyzepro/screens/dashboard/compras/diferenca_pedido_nota_detalhes_page.dart';
import '../../../models/compras/diferenca_pedido_nota_model.dart';
import '../../../models/compras/diferenca_pedido_nota_model_detalhes.dart';
import '../../../repositories/compras/diferenca_pedido_nota_repository_detalhes.dart';
import '../../../services/caches/diferenca_pedido_nota_cache.dart';
import '../../home/menu_principal_page.dart';
/// Página: Diferença Pedido × Nota (Resumo)
///
/// Estrutura replica os “recursos” da tela de Contas a Receber:
///  • Escolha de empresa via `PopupMenuButton`
///  • Seletor de intervalo de datas
///  • Grade de cards de resumo com carregamento individual
///  • Lista (tap‑to‑expand) dos fornecedores divergentes
///  • Cronômetro visual simples enquanto consulta a API
///
/// _Obs.:_  Não há cache nem cronômetro médio → mantemos só o cronômetro
/// instantâneo para não inflar o código.
class DiferencaPedidoNotaPage extends StatefulWidget {
  const DiferencaPedidoNotaPage({super.key});

  @override
  State<DiferencaPedidoNotaPage> createState() => _DiferencaPedidoNotaPageState();
}

class _DiferencaPedidoNotaPageState extends State<DiferencaPedidoNotaPage> with WidgetsBindingObserver {
  /// Future global compartilhado para evitar consultas duplicadas
  static Future<void>? _globalFuture;
  // =============================================
  // Serviços / Repositórios
  // =============================================
  late final AuthService _auth;
  late final ApiClient _api;
  late final DiferencaPedidoNotaRepository _repo;

  // --- Cronômetro médio/histórico ---
  late final TempoExecucaoRepository _tempoRepo;
  // double? _tempoExecucao;
  double? _tempoMedioEstimado;

  final _pageCache = DiferencaPedidoNotaPageCache.instance;

  // =============================================
  // Filtros
  // =============================================
  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  DateTimeRange? _intervalo;
  double _valorMinDif = 5.0;

  // =============================================
  // Estado de UI
  // =============================================
  final Map<int, bool> _cardLoad = {0: true, 1: true, 2: true, 3: true};
  bool _listaLoading = false;

  // Cronômetro simples
  Timer? _timer;
  double _cronometro = 0;

  // Dados
  List<DiferencaPedidoNotaModel> _fornecedores = [];
  int get _totalFornecedores => _fornecedores.length;
  int get _totalItens =>
      _fornecedores.fold(0, (s, f) => s + f.qtdItensDivergentes);
  double get _totalDif =>
      _fornecedores.fold(0.0, (s, f) => s + f.totalDiferencaRs);

  /// Diferença média por item divergente
  double get _difMediaPorItem =>
      _totalItens == 0 ? 0.0 : _totalDif / _totalItens;

  final _fmt = DateFormat('dd/MM/yyyy');

  // Map<idCliFor, List<Empresa>> – quais empresas apresentaram divergência para cada fornecedor
  final Map<int, List<Empresa>> _fornecedorEmpresas = {};
  // Map<idCliFor, Map<idEmpresa, DiferencaPedidoNotaModel>>
  final Map<int, Map<int, DiferencaPedidoNotaModel>> _fornecedorPorEmpresa = {};

  // ==== ALTERAÇÃO 2025-07-27: agora armazenamos a SOMA das quantidades divergentes (nota a mais / a menos) ====
  final Map<int, (double mais, double menos)> _contagemQtdDivergente = {};
  // Map<idCliFor, Map<idEmpresa, (mais, menos)>> – para exibir por empresa na modal
  final Map<int, Map<int, (double mais, double menos)>> _contagemQtdDivergentePorEmpresa = {};

  // Busca de fornecedores
  bool _modoBuscaFornecedores = false;
  final TextEditingController _fornecedorSearchController = TextEditingController();
  String _fornecedorFilter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fornecedorSearchController.addListener(() {
      setState(() {
        _fornecedorFilter = _fornecedorSearchController.text.toLowerCase();
      });
    });
    _auth = AuthService();
    _api = ApiClient(_auth);
    _repo = DiferencaPedidoNotaRepository(_api);
    _tempoRepo = TempoExecucaoRepository();
    _carregarEmpresas();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _fornecedorSearchController.dispose();
    super.dispose();
  }

  // =============================================
  // Carregar empresas (mesma lógica simplificada)
  // =============================================
  Future<void> _carregarEmpresas() async {
    final service = CadLojasService(_api);
    final emps = await service.getEmpresasComNome();
    if (emps.isNotEmpty && emps.first.id != 0) {
      emps.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }
    final hoje = DateTime.now();
    final inicio = DateTime(hoje.year, hoje.month, hoje.day);
    final fim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);

    if (mounted) {
      setState(() {
        _empresas = emps;
        _empresaSelecionada =
        emps.length > 1 ? emps[1] : (emps.isNotEmpty ? emps.first : null);
        _intervalo = DateTimeRange(start: inicio, end: fim);
      });
    }

    // —— Restaura do cache se válido ——
    if (_pageCache.cacheValido) {
      _contagemQtdDivergente.clear();
      setState(() {
        _fornecedores = List<DiferencaPedidoNotaModel>.from(_pageCache.resultados!);
        _empresaSelecionada = _pageCache.empresaSelecionada;
        _intervalo = _pageCache.intervaloSelecionado;
        _valorMinDif = _pageCache.valorMinDif!;
        _cardLoad.updateAll((k, v) => false);
        _listaLoading = false;
        if (_pageCache.contagemQtdDivergente != null) {
          _contagemQtdDivergente.addAll(_pageCache.contagemQtdDivergente!);
        }
      });
      await _inicializarTempoExecucao();
      return;
    }

    await _inicializarTempoExecucao();
    _carregarDados();
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresaSelecionada == null || _intervalo == null) return;
    final dias = _intervalo!.end.difference(_intervalo!.start).inDays;
    final chave = '${_empresaSelecionada!.id}|$dias|dif_ped_nota';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoMedioEstimado = media;
      });
    }
  }

  // =============================================
  // Carregar dados principais
  // =============================================
  Future<void> _carregarDados() async {
    if (_empresaSelecionada == null || _intervalo == null) return;

    // Se já existe uma consulta em andamento, aguarda a mesma.
    if (_globalFuture != null) {
      await _globalFuture;
      return;
    }

    // Dispara nova consulta e armazena na Future global.
    _globalFuture = _carregarDadosInternal();
    await _globalFuture;
    _globalFuture = null; // Libera para próximas execuções.
  }

  Future<void> _carregarDadosInternal() async {
    // Reseta a contagem antes de iniciar nova consulta
    _contagemQtdDivergente.clear();
    _contagemQtdDivergentePorEmpresa.clear();
    // —— Se cache válido, usa‑o e sai ——
    if (_pageCache.cacheValido &&
        _pageCache.empresaSelecionada?.id == _empresaSelecionada?.id &&
        _pageCache.intervaloSelecionado == _intervalo &&
        _pageCache.valorMinDif == _valorMinDif) {
      _contagemQtdDivergente.clear();
      _contagemQtdDivergentePorEmpresa.clear();
      setState(() {
        _fornecedores = List<DiferencaPedidoNotaModel>.from(_pageCache.resultados!);
        _cardLoad.updateAll((key, value) => false);
        _listaLoading = false;
        if (_pageCache.contagemQtdDivergente != null) {
          _contagemQtdDivergente.addAll(_pageCache.contagemQtdDivergente!);
        }
      });
      return;
    }

    final Stopwatch _sw = Stopwatch()..start();

    // ---- Ativa loaders & cronômetro ----
    _cardLoad.updateAll((key, value) => true);
    _listaLoading = true;
    _cronometro = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tickCron());
    if (mounted) setState(() {});

    try {
      // • Se “Todas as Empresas” ⇒ consulta cada empresa (≠0) e agrega resultados
      // • Senão ⇒ consulta apenas a empresa selecionada
      final List<Empresa> alvo = _empresaSelecionada!.id == 0
          ? _empresas.where((e) => e.id != 0).toList()
          : [_empresaSelecionada!];

      // --- Busca paralela, cada empresa com timeout de 30 s ---
      final listas = await Future.wait(
        alvo.map((emp) async {
          try {
            return await _repo
                .getResumo(
              idEmpresa: emp.id,
              valorMinDif: _valorMinDif,
              dataInicial: _intervalo!.start,
              dataFinal: _intervalo!.end,
            )
                .timeout(const Duration(seconds: 30));
          } catch (_) {
            // Falha (timeout / erro) → retorna lista vazia para não travar UI
            return <DiferencaPedidoNotaModel>[];
          }
        }),
      );

      // --- Agrega resultados por fornecedor ---
      final Map<int, DiferencaPedidoNotaModel> agregado = {};
      for (final lista in listas) {
        for (final item in lista) {
          agregado.update(
            item.idCliFor,
                (existente) => existente.copyWith(
              qtdItensDivergentes:
              existente.qtdItensDivergentes + item.qtdItensDivergentes,
              totalDiferencaRs:
              existente.totalDiferencaRs + item.totalDiferencaRs,
            ),
            ifAbsent: () => item,
          );
        }
      }

      // Popula _fornecedorEmpresas e _fornecedorPorEmpresa
      _fornecedorEmpresas.clear();
      _fornecedorPorEmpresa.clear();
      for (int idx = 0; idx < alvo.length; idx++) {
        final emp = alvo[idx];
        final lista = listas[idx];
        for (final item in lista) {
          _fornecedorEmpresas.putIfAbsent(item.idCliFor, () => []).add(emp);
          _fornecedorPorEmpresa
              .putIfAbsent(item.idCliFor, () => {})
              .putIfAbsent(emp.id, () => item);
        }
      }

      setState(() {
        _contagemQtdDivergente.clear(); // limpa os dados anteriores antes de carregar os novos
      });
      if (mounted) {
        setState(() {
          _fornecedores = agregado.values.toList()
            ..sort((a, b) => b.totalDiferencaRs.compareTo(a.totalDiferencaRs));
          // ==== ALTERAÇÃO 2025-07-27: sentinel (-1, -1) como double para indicar "carregando" ====
          _fornecedores.forEach((f) {
            _contagemQtdDivergente[f.idCliFor] = (-1.0, -1.0); // carregando
          });
        });
      }
      // ==== ALTERAÇÃO 2025-07-26: detalhes agora carregam em background, um a um ====
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carregarDetalhesGradualmente();
      });
    } finally {
      // ---- Desliga loaders & cronômetro ----
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _cardLoad.updateAll((key, value) => false);
          _listaLoading = false;
        });
      }
      _sw.stop();
      final dias = _intervalo!.end.difference(_intervalo!.start).inDays;
      final chave = '${_empresaSelecionada!.id}|$dias|dif_ped_nota';
      final tempoReal = _sw.elapsedMilliseconds / 1000;
      try {
        await _tempoRepo.salvarTempo(chave, _sw.elapsedMilliseconds);
      } catch (_) {}
      // Removed setting _tempoExecucao here
      final media = await _tempoRepo.buscarTempoMedio(chave);
      if (mounted) {
        setState(() {
          _tempoMedioEstimado = media;
        });
      }
      // Cache será salvo ao final de _carregarDetalhesGradualmente()
      _globalFuture = null; // Garante liberação mesmo em caso de erro
    }
  }

  // ==== ALTERAÇÃO 2025-07-26: método para carregar os detalhes gradualmente ====
  Future<void> _carregarDetalhesGradualmente() async {
    final detalhesRepo = DiferencaPedidoNotaDetalhesRepository(_api);

    for (final f in _fornecedores) {
      // Já carregado?
      final jaTem = _contagemQtdDivergente[f.idCliFor];
      if (jaTem != null && jaTem.$1 != -1.0 && jaTem.$2 != -1.0) continue;

      try {
        // Busca detalhes para todas as empresas correspondentes (ou apenas a selecionada)
        final List<Empresa> empresasParaBuscar = _empresaSelecionada!.id == 0
            ? (_fornecedorEmpresas[f.idCliFor] ?? [])
            : [_empresaSelecionada!];

        final List<DiferencaPedidoNotaDetalhesModel> todosDetalhes = [];

        for (final emp in empresasParaBuscar) {
          final lista = await detalhesRepo.fetchDetalhes(
            idEmpresa: emp.id,
            idClifor: f.idCliFor,
            valorMinDif: _valorMinDif,
            dataInicial: _intervalo!.start,
            dataFinal: _intervalo!.end,
          );
          // === Quantidades divergentes por EMPRESA ===
          final double somaMaisEmp = lista
              .where((i) => i.qtdNota > i.qtdSolicitada)
              .fold<double>(0.0, (s, i) => s + (i.qtdNota - i.qtdSolicitada));
          final double somaMenosEmp = lista
              .where((i) => i.qtdNota < i.qtdSolicitada)
              .fold<double>(0.0, (s, i) => s + (i.qtdSolicitada - i.qtdNota));
          _contagemQtdDivergentePorEmpresa
              .putIfAbsent(f.idCliFor, () => {})[emp.id] = (somaMaisEmp, somaMenosEmp);
          todosDetalhes.addAll(lista);
        }

        // ==== ALTERAÇÃO 2025-07-27: somatório das quantidades divergentes ====
        final double somaMais = todosDetalhes
            .where((i) => i.qtdNota > i.qtdSolicitada)
            .fold<double>(0.0, (s, i) => s + (i.qtdNota - i.qtdSolicitada));
        final double somaMenos = todosDetalhes
            .where((i) => i.qtdNota < i.qtdSolicitada)
            .fold<double>(0.0, (s, i) => s + (i.qtdSolicitada - i.qtdNota));
        _contagemQtdDivergente[f.idCliFor] = (somaMais, somaMenos);
      } catch (_) {
        // Em caso de erro, evita loader infinito
        _contagemQtdDivergente[f.idCliFor] = (0.0, 0.0);
      }

      if (mounted) {
        setState(() {}); // Atualiza apenas o card editado
      }

      // Salva snapshot parcial no cache para que, se o usuário sair e voltar,
      // a tela reconstrua imediatamente com o que já foi carregado
      if (_empresaSelecionada != null && _intervalo != null) {
        _pageCache.salvar(
          resultados: _fornecedores,
          empresa: _empresaSelecionada!,
          intervalo: _intervalo!,
          valorMinDif: _valorMinDif,
          contagemQtdDivergente: _contagemQtdDivergente,
        );
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Após concluir todos os detalhes, salva no cache completo
    if (_empresaSelecionada != null && _intervalo != null) {
      _pageCache.salvar(
        resultados: _fornecedores,
        empresa: _empresaSelecionada!,
        intervalo: _intervalo!,
        valorMinDif: _valorMinDif,
        contagemQtdDivergente: _contagemQtdDivergente,
      );
    }
  }

  void _tickCron() {
    if (!mounted) return;
    setState(() => _cronometro += 0.2);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed &&
        (_timer == null || !_timer!.isActive)) {
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tickCron());
    }
  }

  /// Mostra as empresas que tiveram divergência com este fornecedor.
  void _mostrarEmpresasModal(DiferencaPedidoNotaModel fornecedor) {
    final mapa = _fornecedorPorEmpresa[fornecedor.idCliFor] ?? {};
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fornecedor.nome,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: mapa.entries.map((e) {
                      final emp = _empresas.firstWhere((el) => el.id == e.key);
                      final dados = e.value;
                      return ListTile(
                        leading: const Icon(Icons.store),
                        title: Text(emp.toString()),
                        subtitle: (() {
                          final tuple = _contagemQtdDivergentePorEmpresa[fornecedor.idCliFor]?[emp.id];
                          final qtdFmt = NumberFormat('##0.000', 'pt_BR');
                          final diferencaFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(dados.totalDiferencaRs);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${dados.qtdItensDivergentes} itens – $diferencaFmt'),
                              const SizedBox(height: 4),
                              if (tuple == null)
                                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              else if (tuple.$1 == 0.0 && tuple.$2 == 0.0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('=', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                                )
                              else Row(
                                children: [
                                  if (tuple.$1 > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow[100],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('+${qtdFmt.format(tuple.$1)}',
                                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                                    ),
                                  if (tuple.$2 > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red[100],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('-${qtdFmt.format(tuple.$2)}',
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                            ],
                          );
                        })(),
                        onTap: () {
                          Navigator.pop(ctx);
                          _abrirDetalhes(fornecedor, emp);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirDetalhes(DiferencaPedidoNotaModel fornecedor, Empresa empresa) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiferencaPedidoNotaDetalhesPage(
          idEmpresa: empresa.id,
          idCliFor: fornecedor.idCliFor,
          valorMinDif: _valorMinDif,
          intervalo: _intervalo!,
          nomeFornecedor: fornecedor.nome,
        ),
      ),
    );
  }

  // =============================================
  // UI helpers
  // =============================================
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _intervalo,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D32),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Color(0xFF2E7D32)),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _intervalo = picked);
      await _inicializarTempoExecucao();
      _carregarDados();
    }
  }

  String _intervaloFmt() {
    if (_intervalo == null) return 'Selecione o intervalo';
    return '${_fmt.format(_intervalo!.start)} - ${_fmt.format(_intervalo!.end)}';
  }

  // =============================================
  // Build
  // =============================================
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
            // ===================================================
            // Filtros (Empresa, Data, Valor mínimo)
            // ===================================================
            if (_empresas.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopupMenuButton<Empresa>(
                    tooltip: 'Selecionar empresa',
                    itemBuilder: (ctx) => _empresas
                        .map((e) => PopupMenuItem(
                      value: e,
                      child: Text(e.toString()),
                    ))
                        .toList(),
                    onSelected: (e) async {
                      setState(() => _empresaSelecionada = e);
                      await _inicializarTempoExecucao();
                      _carregarDados();
                    },
                    child: TextButton.icon(
                      icon:
                      const Icon(Icons.business, size: 18, color: Colors.black87),
                      label: Text(
                        _empresaSelecionada?.toString() ?? 'Empresa',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87),
                      ),
                      onPressed: null,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_intervaloFmt(),
                        overflow: TextOverflow.ellipsis),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Maior que:'),
                      Expanded(
                        child: Slider(
                          min: 5,
                          max: 1000,
                          divisions: ((1000 - 5) ~/ 5),
                          value: _valorMinDif,
                          label: _valorMinDif.toStringAsFixed(0),
                          onChanged: (v) {
                            setState(() => _valorMinDif = v);
                          },
                          onChangeEnd: (_) => _carregarDados(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                            .format(_valorMinDif.round()),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Dif. Pedido x Nota',
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
                ],
              ),

            const SizedBox(height: 12),

            // ===================================================
            // Cards de Resumo
            // ===================================================
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
              itemBuilder: (ctx, i) {
                final loading = _cardLoad[i] ?? false;
                if (loading) {
                  return const _CardLoader();
                }
                switch (i) {
                  case 0:
                    return _ResumoCard(
                      title: 'Fornecedores',
                      value: NumberFormat.decimalPattern('pt_BR')
                          .format(_totalFornecedores),
                      icon: Icons.factory,
                    );
                  case 1:
                    return _ResumoCard(
                      title: 'Diferença Tot.',
                      value: NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                          .format(_totalDif),
                      icon: Icons.attach_money,
                    );
                  case 2:
                    return _ResumoCard(
                      title: 'Produtos',
                      value: NumberFormat.decimalPattern('pt_BR')
                          .format(_totalItens),
                      icon: Icons.format_list_numbered,
                    );
                  case 3:
                    return _ResumoCard(
                      title: 'Diferença Méd.',
                      value: NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                          .format(_difMediaPorItem),
                      icon: Icons.equalizer,
                    );
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),

            // ===================================================
            // Lista de Fornecedores
            // ===================================================
            // const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: _modoBuscaFornecedores
                      ? TextField(
                    controller: _fornecedorSearchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Filtrar...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 0),
                    ),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Fornecedores',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (_fornecedores.isNotEmpty && _contagemQtdDivergente.length < _fornecedores.length)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_modoBuscaFornecedores ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      if (_modoBuscaFornecedores) {
                        _modoBuscaFornecedores = false;
                        _fornecedorSearchController.clear();
                        _fornecedorFilter = '';
                      } else {
                        _modoBuscaFornecedores = true;
                      }
                    });
                  },
                ),
              ],
            ),

            if (_listaLoading)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: _fornecedores
                    .where((f) => f.nome.toLowerCase().contains(_fornecedorFilter))
                    .map((f) {
                  final contagem = _contagemQtdDivergente[f.idCliFor] ?? (0.0, 0.0);
                  return _FornecedorCard(
                    fornecedor: f,
                    qtdMais: contagem.$1,
                    qtdMenos: contagem.$2,
                    onTap: () {
                      // ❗️ Verifica se TODOS os fornecedores já carregaram os detalhes
                      final carregamentoCompleto = _fornecedores.every((f) {
                        final contagem = _contagemQtdDivergente[f.idCliFor];
                        return contagem != null && contagem.$1 != -1.0 && contagem.$2 != -1.0;
                      });

                      if (!carregamentoCompleto) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Aguarde o carregamento de todos os detalhes antes de navegar.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }

                      if (_empresaSelecionada == null || _intervalo == null) return;

                      if (_empresaSelecionada!.id == 0) {
                        final empresas = _fornecedorEmpresas[f.idCliFor] ?? [];
                        if (empresas.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nenhuma empresa com diferença para este fornecedor.')),
                          );
                          return;
                        }
                        if (empresas.length == 1) {
                          _abrirDetalhes(f, empresas.first);
                        } else {
                          _mostrarEmpresasModal(f);
                        }
                        return;
                      }

                      _abrirDetalhes(f, _empresaSelecionada!);
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// UI COMPONENTES
// ===================================================================

class _ResumoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _ResumoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

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
      child: Stack(
        children: [
          // Main card column
          Column(
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
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // info button removed
        ],
      ),
    );
  }
}

class _CardLoader extends StatelessWidget {
  const _CardLoader();
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
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
}

// ==== ALTERAÇÃO 2025-07-27: agora exibimos a quantidade SOMADA divergente ====
class _FornecedorCard extends StatelessWidget {
  final DiferencaPedidoNotaModel fornecedor;
  final VoidCallback onTap;
  final double qtdMais;
  final double qtdMenos;

  const _FornecedorCard({
    required this.fornecedor,
    required this.onTap,
    this.qtdMais = 0.0,
    this.qtdMenos = 0.0,
  });
  @override
  Widget build(BuildContext context) {
    final difFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
        .format(fornecedor.totalDiferencaRs);
    final itensFmt = '${fornecedor.qtdItensDivergentes} itens';
    final qtdFmt = NumberFormat('##0.000', 'pt_BR'); // formato com vírgula

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
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
            // ---------- Nome do fornecedor ----------
            Text(
              fornecedor.nome,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // ---------- Total diferença (R$) ----------
            Row(
              children: [
                const Icon(Icons.paid, size: 20, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: difFmt,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ---------- Itens divergentes com indicadores ----------
            Row(
              children: [
                const Icon(Icons.format_list_numbered, size: 20, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    itensFmt,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
                // Chips de divergência:
                if (qtdMais == -1.0 && qtdMenos == -1.0)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (qtdMais == 0.0 && qtdMenos == 0.0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '=',
                      // ajuste typo
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  )
                else ...[
                    if (qtdMais > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: Colors.yellow[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '+${qtdFmt.format(qtdMais)}',
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (qtdMenos > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '-${qtdFmt.format(qtdMenos)}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
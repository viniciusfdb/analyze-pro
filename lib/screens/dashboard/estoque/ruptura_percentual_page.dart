import 'package:flutter/material.dart';
import 'dart:async';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import 'package:analyzepro/api/api_client.dart';

import 'package:analyzepro/services/auth_service.dart';
import '../../../models/cadastros/cad_lojas.dart';
import '../../../services/cad_lojas_service.dart';
import '../../../services/local_estoque_service.dart';
import '../../../models/estoque/ruptura_percentual.dart';
import '../../../repositories/estoque/ruptura_percentual_repository.dart';
import '../../home/menu_principal_page.dart';

/// Cache simples para manter os resultados ao navegar para fora e voltar.
class _RupturaPercentualPageCache {
  static final _RupturaPercentualPageCache instance = _RupturaPercentualPageCache._();
  _RupturaPercentualPageCache._();

  List<RupturaPercentual>? resultados;
  Empresa? empresa;
  Map<String, dynamic>? local;
  DateTime? timestamp;
  bool? expBalanca;

  static const _ttl = Duration(minutes: 30);

  bool get cacheValido {
    if (resultados == null || empresa == null || local == null || timestamp == null) return false;
    return DateTime.now().difference(timestamp!) < _ttl;
  }

  void salvar({
    required List<RupturaPercentual> data,
    required Empresa emp,
    required Map<String, dynamic> loc,
    required bool expBalancaFlag,
  }) {
    resultados = List<RupturaPercentual>.from(data);
    empresa = emp;
    local = Map<String, dynamic>.from(loc);
    expBalanca = expBalancaFlag;
    timestamp = DateTime.now();
  }
}

class RupturaPercentualPage extends StatefulWidget {
  const RupturaPercentualPage({Key? key}) : super(key: key);

  @override
  _RupturaPercentualPageState createState() => _RupturaPercentualPageState();
}

class _RupturaPercentualPageState extends State<RupturaPercentualPage> with WidgetsBindingObserver {
  // Cache da página (empresa + local + resultados)
  static final _pageCache = _RupturaPercentualPageCache.instance;
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  final ApiClient _apiClient = ApiClient(AuthService());
  late final CadLojasService _lojasService;
  late final LocalEstoqueService _estoqueService;
  late final RupturaPercentualRepository _repo;

  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoMedioEstimado;

  List<Empresa> _empresas = [];
  List<Map<String, dynamic>> _locais = [];
  Empresa? _selectedEmpresa;
  Map<String, dynamic>? _selectedLocal;
  bool _expBalanca = false;

  bool _loadingData = false;

  // Grouping state variables
  bool _groupSecao = true;
  bool _groupDivisao = false;
  List<Map<String, dynamic>> _groupResumo = [];
  List<RupturaPercentual> _allData = [];
  bool _hasFetched = false;

  /// Future global compartilhado para evitar consultas duplicadas
  static Future<void>? _globalFuture;

  /// Momento de início da consulta global – usado para manter o cronômetro ativo
  static DateTime? _globalConsultaInicio;

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
    _lojasService = CadLojasService(_apiClient);
    _estoqueService = LocalEstoqueService(_apiClient);
    _repo = RupturaPercentualRepository(_apiClient);
    _tempoRepo = TempoExecucaoRepository();
    _carregarEmpresas();
  }

  Future<void> _carregarEmpresas() async {
    try {
      final empresas = await _lojasService.getEmpresasComNome();
      setState(() {
        _empresas = empresas;
      });
      if (_empresas.isNotEmpty) {
        // Restaura empresa do cache se ainda existir na lista
        if (_pageCache.cacheValido &&
            _pageCache.empresa != null &&
            _empresas.any((e) => e.id == _pageCache.empresa!.id)) {
          _selectedEmpresa =
              _empresas.firstWhere((e) => e.id == _pageCache.empresa!.id);
        } else {
          _selectedEmpresa = _empresas.first;
        }
        await _inicializarTempoExecucao();
      }
      await _loadFilters();
      _cronometro = 0.0;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar empresas: $e')),
      );
    }
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_selectedEmpresa == null) return;
    final chave = '${_selectedEmpresa!.id}';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoMedioEstimado = media;
      });
    }
  }

  Future<void> _loadFilters() async {
    if (_selectedEmpresa == null) return;
    try {
      final locais = await _estoqueService.getLocaisEstoque();
      setState(() {
        _locais = locais;

        // 1. Determina o local selecionado
        if (_selectedLocal != null &&
            _locais.any((m) =>
                m['idlocalestoque'] == _selectedLocal!['idlocalestoque'])) {
          // Mantém o local já selecionado se ele ainda existe
          _selectedLocal = _locais.firstWhere((m) =>
              m['idlocalestoque'] == _selectedLocal!['idlocalestoque']);
        } else if (_pageCache.cacheValido &&
            _pageCache.local != null &&
            _locais.any((m) =>
                m['idlocalestoque'] == _pageCache.local!['idlocalestoque'])) {
          // Caso contrário, tenta restaurar do cache
          _selectedLocal = _locais.firstWhere((m) =>
              m['idlocalestoque'] == _pageCache.local!['idlocalestoque']);
        } else if (_locais.isNotEmpty) {
          // Fallback para o primeiro local
          _selectedLocal = _locais.first;
        }

        // 2. Se cache válido cobre empresa + local atual, restaura dados imediatamente
        if (_pageCache.cacheValido &&
            _pageCache.empresa?.id == _selectedEmpresa?.id &&
            _pageCache.local?['idlocalestoque'] ==
                _selectedLocal?['idlocalestoque'] &&
            _pageCache.expBalanca == _expBalanca) {
          _allData = List<RupturaPercentual>.from(_pageCache.resultados!);
          _hasFetched = true;
        }
      });

      // Caso tenhamos restaurado dados do cache, aplica agrupamento
      if (_hasFetched && mounted) {
        _applyGrouping();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar locais: $e')),
      );
    }
  }

  Future<void> _fetchData() async {
    if (_selectedEmpresa == null || _selectedLocal == null) return;

    // Se cache válido cobre empresa + local atual, usa-o sem buscar
    if (_pageCache.cacheValido &&
        _pageCache.empresa?.id == _selectedEmpresa?.id &&
        _pageCache.local?['idlocalestoque'] ==
            _selectedLocal?['idlocalestoque'] &&
        _pageCache.expBalanca == _expBalanca) {
      setState(() {
        _allData = List<RupturaPercentual>.from(_pageCache.resultados!);
        _hasFetched = true;
        _loadingData = false;
      });
      _applyGrouping();
      return;
    }

    setState(() {
      _loadingData = true;
    });

    // Se já existe consulta em andamento, apenas aguarda.
    if (_globalFuture != null) {
      _startCronometro();
      await _globalFuture;
      setState(() => _loadingData = false);
      return;
    }

    _cronometro = 0.0;
    _globalConsultaInicio = DateTime.now();
    _startCronometro();

    final stopwatch = Stopwatch()..start();

    _globalFuture = () async {
      try {
        final list = await _repo.fetchRupturaPercentual(
          idEmpresa: _selectedEmpresa!.id,
          idLocalEstoque: _selectedLocal!['idlocalestoque'] as int,
          expBalanca: _expBalanca,
        );
        // Salva resultados no cache *antes* de qualquer setState
        _pageCache.salvar(
          data: list,
          emp: _selectedEmpresa!,
          loc: _selectedLocal!,
          expBalancaFlag: _expBalanca,
        );
        if (mounted) {
          setState(() {
            _allData = list;
            _hasFetched = true;
            _applyGrouping();
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao carregar dados: $e')),
          );
        }
      } finally {
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        stopwatch.stop();
        final tempoMs = stopwatch.elapsedMilliseconds;
        final chave = '${_selectedEmpresa!.id}';
        final tempoReal = tempoMs / 1000;
        try {
          await _tempoRepo.salvarTempo(chave, tempoMs);
        } catch (_) {}
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _tempoMedioEstimado = media;
            _loadingData = false;
          });
        }
        _globalFuture = null;
      }
    }();

    await _globalFuture;
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cronometroTimer?.cancel();
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

  void _applyGrouping() {
    final Map<int, List<RupturaPercentual>> groups = {};
    for (var item in _allData) {
      final key = _groupSecao ? item.idSecao : item.idDivisao;
      groups.putIfAbsent(key, () => []).add(item);
    }
    final resumo = groups.entries.map((e) {
      final list = e.value;
      // Compute percentage: for sections use first.percRuptura; for divisions aggregate
      final double perc = _groupSecao
          ? list.first.percRuptura
          : (list.fold<int>(0, (s, i) => s + i.skusAtivos) > 0
              ? list.fold<int>(0, (s, i) => s + i.skusRuptura) /
                  list.fold<int>(0, (s, i) => s + i.skusAtivos) *
                  100
              : 0);
      return {
        _groupSecao ? 'idsecao' : 'iddivisao': e.key,
        _groupSecao ? 'secao' : 'divisao': _groupSecao ? list.first.descrSecao : list.first.descrDivisao,
        'perc': perc,
      };
    }).toList()
      ..sort((a, b) => (b['perc'] as double).compareTo(a['perc'] as double));
    setState(() {
      _groupResumo = resumo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(builder: (context) {
          return IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(context).openDrawer(),
          );
        }),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Empresa selection (ContasReceberPage style)
            IgnorePointer(
              ignoring: _loadingData,
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
                  setState(() {
                    _selectedEmpresa = empresa;
                  });
                  await _inicializarTempoExecucao();
                },
                tooltip: 'Selecionar empresa',
                child: TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                  label: Text(
                    _selectedEmpresa?.toString() ?? 'Empresa',
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
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Local selection
            PopupMenuButton<Map<String, dynamic>>(
              onSelected: (local) {
                setState(() => _selectedLocal = local);
              },
              itemBuilder: (context) {
                return _locais
                    .map((m) => PopupMenuItem(
                  value: m,
                  child: Text(m['descrlocal'] as String),
                ))
                    .toList();
              },
              child: TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.store, size: 18, color: Colors.black87),
                label: Text(
                  _selectedLocal?['descrlocal'] ?? 'Selecione o local',
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
              ),
            ),
            const SizedBox(height: 8),
            // Exp balanca switch (label changed)
            Row(
              children: [
                const Text('Apenas Pesáveis?  ', style: TextStyle(fontSize: 16)),
                Switch(
                  value: _expBalanca,
                  onChanged: (v) {
                    setState(() => _expBalanca = v);
                    _fetchData(); // dispara nova busca com o novo filtro
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('Seção'),
                  selected: _groupSecao,
                  onSelected: (v) {
                    setState(() {
                      _groupSecao = true; _groupDivisao = false;
                      if (_hasFetched) _applyGrouping();
                    });
                  },
                  backgroundColor: Colors.grey.shade200,
                  selectedColor: Colors.grey.shade200,
                  checkmarkColor: Colors.black87,
                  labelStyle: const TextStyle(color: Colors.black87),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: _groupSecao ? Colors.black87 : Colors.transparent),
                  ),
                ),
                FilterChip(
                  label: const Text('Divisão'),
                  selected: _groupDivisao,
                  onSelected: (v) {
                    setState(() {
                      _groupDivisao = true; _groupSecao = false;
                      if (_hasFetched) _applyGrouping();
                    });
                  },
                  backgroundColor: Colors.grey.shade200,
                  selectedColor: Colors.grey.shade200,
                  checkmarkColor: Colors.black87,
                  labelStyle: const TextStyle(color: Colors.black87),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: _groupDivisao ? Colors.black87 : Colors.transparent),
                  ),
                ),
                FilterChip(
                  label: const Text('Buscar'),
                  selected: false,
                  onSelected: _loadingData ? null : (_) => _fetchData(),
                  backgroundColor: Colors.grey.shade200,
                  selectedColor: Colors.grey.shade200,
                  labelStyle: const TextStyle(color: Colors.black87),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.transparent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Ruptura Percentual',
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
            Builder(
              builder: (context) {
                if (_loadingData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!_hasFetched || _allData.isEmpty) {
                  return const Center(child: Text('Aplique local de estoque e clique em Buscar'));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasFetched)
                      GridView.builder(
                        itemCount: _groupResumo.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 2.0),
                        itemBuilder: (ctx, idx) {
                          final entry = _groupResumo[idx];
                          final keyLabel = _groupSecao ? entry['secao'] : entry['divisao'];
                          final perc = entry['perc'] as double;
                          return _DashboardCard(
                            title: keyLabel as String,
                            value: '${perc.toStringAsFixed(2)}%',
                            icon: Icons.category,
                            iconColor: const Color(0xFF2E7D32),
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
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  const _DashboardCard({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: null,
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
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
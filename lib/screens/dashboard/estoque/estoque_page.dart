import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../repositories/estoque/inventario_estoque_repository.dart';
import '../../home/menu_principal_page.dart';
import '../../../models/cadastros/cad_lojas.dart';
import '../../../services/cad_lojas_service.dart';
import '../../../api/api_client.dart';
import '../../../services/auth_service.dart';
// === NOVO IMPORT 22-06-2025: cache da tela Estoque
import '../../../services/caches/estoque_page_cache.dart';
// === NOVO IMPORT 28-06-2025: tempo de execução
import '../../../repositories/cronometro/tempo_execucao_repository.dart';

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

// === ALTERAÇÃO 22-06-2025: adiciona WidgetsBindingObserver
class _EstoquePageState extends State<EstoquePage> with WidgetsBindingObserver {
  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  // Inicia como não‑carregando; será ativado dentro de _carregarEstoque()
  Map<int, bool> _cardLoadStatus = {0: false};
  // === CONTROLE DE REQUISIÇÃO GLOBAL 24‑06‑2025 ===
  static Future<void>? _globalFuture;
  // Momento de início da consulta global – usado para manter o cronômetro ativo
  static DateTime? _globalConsultaInicio;
  /// Inicia ou reinicia o cronômetro visual baseado em [_globalConsultaInicio].
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsedMs = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() {
        _cronometro = elapsedMs / 1000;
      });
    });
  }
  // === MEMÓRIA DE SELEÇÃO ENTRE INSTÂNCIAS 25‑06‑2025
  static Empresa? _lastEmpresaSelecionada;
  // === CACHE DE EMPRESAS 27‑06‑2025 (evita GET repetido ao cad_lojas) ===
  static List<Empresa>? _cachedEmpresas;
  static DateTime? _empresasTimestamp;
  static const int _empresasTtlMin = 30; // minutos
  // Getter de conveniência para loading estoque
  bool get _isLoadingEstoque => _cardLoadStatus[0] == true;
  double _qtdAtualEstoque = 0.0;
  double _custoMedio = 0.0;
  double _valorTotalEstoque = 0.0;
  // Sessão única de autenticação e API
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final InventarioEstoqueRepository _estoqueRepository;
  late final CadLojasService _cadLojasService;
  String _qtdFmt = '0';
  String _valorFmt = 'R\$ 0,00';
  String _custoFmt = 'R\$ 0,00';

  // === NOVOS CAMPOS 28-06-2025 ===
  late final TempoExecucaoRepository _tempoRepo;
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  double? _tempoMedioEstimado;

  // === FLAGS DE CICLO DE VIDA 22-06-2025 ===

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _estoqueRepository = InventarioEstoqueRepository(_apiClient);
    _cadLojasService = CadLojasService(_apiClient);
    _tempoRepo = TempoExecucaoRepository();
    _carregarEmpresas();
  }

  Future<void> _inicializarTempoExecucao() async {
    final id = _empresaSelecionada?.id ?? 0;
    final chave = '$id|estoque';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media = await _tempoRepo.buscarTempoMedio(chave);
    setState(() {
      _cronometro = ultimo ?? 0.0;
      _tempoMedioEstimado = media;
    });
  }

  Future<void> _carregarEmpresas() async {
    List<Empresa> empresas;

    // --- Usa cache se não expirou ---
    final bool cacheOk = _cachedEmpresas != null &&
        _empresasTimestamp != null &&
        DateTime.now().difference(_empresasTimestamp!).inMinutes < _empresasTtlMin;

    if (cacheOk) {
      empresas = List<Empresa>.from(_cachedEmpresas!);
    } else {
      empresas = await _cadLojasService.getEmpresasComNome();
      _cachedEmpresas = List<Empresa>.from(empresas);
      _empresasTimestamp = DateTime.now();
    }

    // Garante opcão "Todas as Empresas" apenas uma vez
    if (empresas.isEmpty || empresas.first.id != 0) {
      empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }

    // === VERIFICA CACHE 22-06-2025 ===
    if (EstoquePageCache.instance.cacheValido && _globalFuture == null) {
      // ✔️ Nenhuma requisição pendente → pode usar o cache
      _cardLoadStatus[0] = false;
      if (mounted) {
        setState(() {
          _empresas = empresas;
          _empresaSelecionada =
              _lastEmpresaSelecionada ?? EstoquePageCache.instance.empresaSelecionada;
          _qtdAtualEstoque   = EstoquePageCache.instance.qtd;
          _valorTotalEstoque = EstoquePageCache.instance.valor;
          _custoMedio        = EstoquePageCache.instance.custo;
          _qtdFmt   = NumberFormat.decimalPattern('pt_BR').format(_qtdAtualEstoque);
          _valorFmt = NumberFormat.simpleCurrency(locale: 'pt_BR')
              .format(_valorTotalEstoque);
          _custoFmt = NumberFormat.simpleCurrency(locale: 'pt_BR')
              .format(_custoMedio);
        });
      }
      // --- Carrega tempo médio estimado do cronômetro ao reabrir com cache ---
      final empresa = _lastEmpresaSelecionada ?? EstoquePageCache.instance.empresaSelecionada;
      if (empresa != null) {
        final chave = '${empresa.id}|estoque';
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _cronometro = 0.0;
            _tempoMedioEstimado = media;
          });
        }
      }
      return;
    } else if (_globalFuture != null) {
      // 🔄 Existe uma requisição global em progresso → mostra loader & aguarda
      _cardLoadStatus[0] = true;
      // Reinicia cronômetro para acompanhar a consulta já em andamento
      _startCronometro();
      if (mounted) {
        setState(() {
          _empresas = empresas;
          _empresaSelecionada =
              _lastEmpresaSelecionada ?? EstoquePageCache.instance.empresaSelecionada;
        });
      }

      await _globalFuture; // espera a requisição terminar

      // ✔️ Depois que a requisição finaliza, lemos o cache atualizado
      _cardLoadStatus[0] = false;
      if (mounted) {
        setState(() {
          _empresaSelecionada =
              _lastEmpresaSelecionada ?? EstoquePageCache.instance.empresaSelecionada;
          _qtdAtualEstoque   = EstoquePageCache.instance.qtd;
          _valorTotalEstoque = EstoquePageCache.instance.valor;
          _custoMedio        = EstoquePageCache.instance.custo;
          _qtdFmt   = NumberFormat.decimalPattern('pt_BR').format(_qtdAtualEstoque);
          _valorFmt = NumberFormat.simpleCurrency(locale: 'pt_BR')
              .format(_valorTotalEstoque);
          _custoFmt = NumberFormat.simpleCurrency(locale: 'pt_BR')
              .format(_custoMedio);
        });
      }
      return;
    }

    setState(() {
      _empresas = empresas;
      _empresaSelecionada = _lastEmpresaSelecionada ??
          empresas.firstWhere(
            (e) => e.id == 1,
            orElse: () => empresas.first,
          );
    });

    if (_empresaSelecionada != null) {
      await _inicializarTempoExecucao();
      _carregarEstoque();
    }
  }

  Future<void> _carregarEstoque() async {
    final stopwatch = Stopwatch()..start();
    bool consultaNecessaria = true;

    if (_empresaSelecionada == null) return;
    setState(() {
      _cronometro = 0.0;
    });
    _cronometro = 0.0;
    _globalConsultaInicio = DateTime.now();
    _startCronometro();

    // === Se já houver requisição global em andamento, apenas aguarda ===
    if (_globalFuture != null) {
      _cardLoadStatus[0] = true;
      if (mounted) setState(() {});
      await _globalFuture;
      _cardLoadStatus[0] = false;
      if (mounted) setState(() {});
      consultaNecessaria = false;
      stopwatch.stop();
      final tempoMs = stopwatch.elapsedMilliseconds;
      final chave = '${_empresaSelecionada?.id}|estoque';
      _cronometro = tempoMs / 1000;
      _tempoMedioEstimado = await _tempoRepo.buscarTempoMedio(chave);
      return;
    }

    // === Se já está carregando nesta instância, não dispara novamente ===
    if (_cardLoadStatus[0] == true) {
      debugPrint('⏳ Requisição já em andamento nesta instância');
      return;
    }

    _cardLoadStatus[0] = true;
    if (mounted) setState(() {});

    _globalFuture = () async {
      try {
        final lista = await _estoqueRepository.getInventarioEstoque(
          empresa: _empresaSelecionada!.id == 0
              ? null
              : _empresaSelecionada!.id,
        );

        final somaQtd = lista.fold(0.0, (total, item) => total + item.qtdAtualEstoque);
        final somaValorTotal = lista.fold(0.0, (total, item) => total + item.valorTotal);
        final custoMedio = lista.isEmpty ? 0.0 : somaValorTotal / somaQtd;

        if (mounted) {
          setState(() {
            _qtdAtualEstoque = somaQtd;
            _valorTotalEstoque = somaValorTotal;
            _custoMedio = custoMedio;
            _qtdFmt = NumberFormat.decimalPattern('pt_BR').format(_qtdAtualEstoque);
            _valorFmt = NumberFormat.simpleCurrency(locale: 'pt_BR').format(_valorTotalEstoque);
            _custoFmt = NumberFormat.simpleCurrency(locale: 'pt_BR').format(_custoMedio);
          });
        }

        _lastEmpresaSelecionada = _empresaSelecionada;
        // === SALVA CACHE 22-06-2025 ===
        EstoquePageCache.instance.salvar(
          empresa: _empresaSelecionada!,
          qtd: _qtdAtualEstoque,
          custo: _custoMedio,
          valor: _valorTotalEstoque,
        );
      } catch (e) {
        debugPrint('❌ Erro ao carregar resumo de estoque: $e');
        if (mounted) {
          setState(() {
            _qtdAtualEstoque = 0.0;
            _valorTotalEstoque = 0.0;
            _custoMedio = 0.0;
            _qtdFmt = '0';
            _valorFmt = 'R\$ 0,00';
            _custoFmt = 'R\$ 0,00';
          });
        }
      } finally {
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        stopwatch.stop();
        final tempoMs = stopwatch.elapsedMilliseconds;
        final chave = '${_empresaSelecionada?.id}|estoque';
        final tempoReal = tempoMs / 1000;
        if (consultaNecessaria) {
          await _tempoRepo.salvarTempo(chave, tempoMs);
        }
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _cronometro = tempoReal;
            _tempoMedioEstimado = media;
          });
        }

        _cardLoadStatus[0] = false;
        if (mounted) setState(() {});
        _globalFuture = null;
      }
    }();
    await _globalFuture;
    return;
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
        actions: [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // === BLOCO SELEÇÃO DE EMPRESA (23‑06‑2025) ===
                IgnorePointer(
                  ignoring: _isLoadingEstoque,
                  child: Opacity(
                    opacity: _isLoadingEstoque ? 0.5 : 1.0,
                    child: PopupMenuButton<Empresa>(
                      color: Colors.white,
                      itemBuilder: (context) {
                        return _empresas.map((empresa) {
                          return PopupMenuItem<Empresa>(
                            value: empresa,
                            child: Text('${empresa.id} - ${empresa.nome}'),
                          );
                        }).toList();
                      },
                      onSelected: (empresa) async {
                        _lastEmpresaSelecionada = empresa; // guarda para próximas instâncias
                        setState(() {
                          _empresaSelecionada = empresa;
                        });
                        await _inicializarTempoExecucao();
                        _carregarEstoque();
                      },
                      tooltip: 'Selecionar empresa',
                      child: TextButton.icon(
                        icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                        label: Text(
                          '${_empresaSelecionada?.id ?? 0} - ${_empresaSelecionada?.nome ?? 'Todas as Empresas'}',
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
                // const SizedBox(height: 8), // REMOVIDO espaçador após seleção de empresa
              ],
            ),
            const SizedBox(height: 18),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Resumo do Estoque',
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
                switch (index) {
                  case 0:
                    return _DashboardCard(
                      title: "Quantidade",
                      value: _qtdFmt,
                      icon: Icons.inventory,
                      isLoading: _cardLoadStatus[0] ?? false,
                    );
                  case 1:
                    return _DashboardCard(
                      title: "Valor Total",
                      value: _valorFmt,
                      icon: Icons.attach_money,
                      isLoading: _cardLoadStatus[0] ?? false,
                    );
                  default:
                    return _DashboardCard(
                      title: "Custo Médio",
                      value: _custoFmt,
                      icon: Icons.price_change,
                      isLoading: _cardLoadStatus[0] ?? false,
                    );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // === LIMPA OBSERVER 22-06-2025 ===
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

}


class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool isLoading;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: null,
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
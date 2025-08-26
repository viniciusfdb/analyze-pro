import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_client.dart';
import '../../repositories/vendas/faturamento_com_lucro_repository.dart';
import '../../services/auth_service.dart';
import '../../services/config_validation.dart';
import '../dashboard/vendas/vendas_page.dart';
import 'menu_principal_page.dart';
import '../../models/cadastros/cad_lojas.dart';
import '../../services/cad_lojas_service.dart';
import '../../models/vendas/faturamento_com_lucro_model.dart';


class _ResumoEmpresa {
  final String totalFmt;
  final String lucroFmt;
  final String devolucoesFmt;
  final bool vendasMelhoraram;
  final bool lucroMelhorou;
  final bool devolucoesPioraram;
  const _ResumoEmpresa({
    required this.totalFmt,
    required this.lucroFmt,
    required this.devolucoesFmt,
    required this.vendasMelhoraram,
    required this.lucroMelhorou,
    required this.devolucoesPioraram,
  });
}


class _LinhaResumo {
  final int idEmpresa;
  final List<FaturamentoComLucro> itens;
  const _LinhaResumo(this.idEmpresa, this.itens);
}


class _BrutosEmpresa {
  final double total;
  final double lucro;
  final double devol;
  const _BrutosEmpresa(this.total, this.lucro, this.devol);
}

class _HomeResumoCache {
  static DateTime? lastUpdated;
  static String dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  static Map<int, _BrutosEmpresa> hojePorEmpresa = <int, _BrutosEmpresa>{};
  static Map<int, _BrutosEmpresa> ontemPorEmpresa = <int, _BrutosEmpresa>{};
  static Map<int, _ResumoEmpresa> resumosPorEmpresa = <int, _ResumoEmpresa>{};
  static String totalFmt = 'R\u0024\u00a00,00';
  static String lucroFmt = 'R\u0024\u00a00,00';
  static String devolucoesFmt = 'R\u0024\u00a00,00';
  static bool vendasMelhoraram = false;
  static bool lucroMelhorou = false;
  static bool devolucoesPioraram = false;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  static const Duration cacheDuration = Duration(minutes: 30);

  String _todayKeySuffix() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _cacheKeyTotalVenda(int idEmpresa) => 'cache_total_venda_${_todayKeySuffix()}_$idEmpresa';
  String _cacheKeyLucro(int idEmpresa) => 'cache_lucro_${_todayKeySuffix()}_$idEmpresa';
  String _cacheKeyDevolucoes(int idEmpresa) => 'cache_devolucoes_${_todayKeySuffix()}_$idEmpresa';
  String _cacheKeyResumoTimestamp(int idEmpresa) => 'cache_resumo_timestamp_${_todayKeySuffix()}_$idEmpresa';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final AuthService _authService;
  late final ApiClient _apiClient;

  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  String _totalVendaHojeFmt = 'R\$ 0,00';
  String _lucroHojeFmt = 'R\$ 0,00';
  String _devolucoesHojeFmt = 'R\$ 0,00';
  bool _isLoadingResumo = false;

  bool _vendasMelhoraram = false;
  bool _lucroMelhorou = false;
  bool _devolucoesPioraram = false;

  // Resumo por empresa quando "Todas as Empresas" está selecionado
  Map<int, _ResumoEmpresa> _resumosPorEmpresa = <int, _ResumoEmpresa>{};

  bool _autoRefreshAtivo = true;

  // Controle de concorrência / reentrância e cache em memória
  int _loadToken = 0;
  final Map<String, List<FaturamentoComLucro>> _memCache = <String, List<FaturamentoComLucro>>{};
  String _memKey(int id, DateTime d) => '$id|${DateFormat('yyyy-MM-dd').format(d)}';
  List<FaturamentoComLucro>? _getMem(int id, DateTime d) => _memCache[_memKey(id, d)];
  void _putMem(int id, DateTime d, List<FaturamentoComLucro> v) => _memCache[_memKey(id, d)] = v;

  // Parciais acumuladas por empresa (para atualização incremental)
  final Map<int, _BrutosEmpresa> _hojePorEmpresa = <int, _BrutosEmpresa>{};
  final Map<int, _BrutosEmpresa> _ontemPorEmpresa = <int, _BrutosEmpresa>{};

  Future<List<T>> _runBatches<T>(List<Future<T> Function()> tasks, {int concurrency = 4}) async {
    final results = <T>[];
    final queue = List<Future<T> Function()>.from(tasks);
    final running = <Future<void>>[];

    void startNext() {
      if (queue.isEmpty) return;
      final fn = queue.removeAt(0);
      final f = fn().then((r) => results.add(r));
      running.add(f.whenComplete(() {
        startNext();
      }));
    }

    final initial = concurrency.clamp(1, queue.length);
    for (var i = 0; i < initial; i++) {
      startNext();
    }

    await Future.wait(running);
    return results;
  }

  String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  bool _hydrateFromSessionCacheIfValid() {
    if (_empresaSelecionada?.id != 0) return false;
    final now = DateTime.now();
    if (_HomeResumoCache.lastUpdated == null) return false;
    if (_HomeResumoCache.dateKey != _todayKey()) return false;
    if (now.difference(_HomeResumoCache.lastUpdated!) > cacheDuration) return false;
    if (_HomeResumoCache.resumosPorEmpresa.isEmpty) return false;

    setState(() {
      _resumosPorEmpresa = Map<int, _ResumoEmpresa>.from(_HomeResumoCache.resumosPorEmpresa);
      _hojePorEmpresa
        ..clear()
        ..addAll(_HomeResumoCache.hojePorEmpresa);
      _ontemPorEmpresa
        ..clear()
        ..addAll(_HomeResumoCache.ontemPorEmpresa);
      _totalVendaHojeFmt = _HomeResumoCache.totalFmt;
      _lucroHojeFmt = _HomeResumoCache.lucroFmt;
      _devolucoesHojeFmt = _HomeResumoCache.devolucoesFmt;
      _vendasMelhoraram = _HomeResumoCache.vendasMelhoraram;
      _lucroMelhorou = _HomeResumoCache.lucroMelhorou;
      _devolucoesPioraram = _HomeResumoCache.devolucoesPioraram;
      _isLoadingResumo = false;
    });
    return true;
  }

  void _saveSessionCacheFromState() {
    _HomeResumoCache.hojePorEmpresa = Map<int, _BrutosEmpresa>.from(_hojePorEmpresa);
    _HomeResumoCache.ontemPorEmpresa = Map<int, _BrutosEmpresa>.from(_ontemPorEmpresa);
    _HomeResumoCache.resumosPorEmpresa = Map<int, _ResumoEmpresa>.from(_resumosPorEmpresa);
    _HomeResumoCache.totalFmt = _totalVendaHojeFmt;
    _HomeResumoCache.lucroFmt = _lucroHojeFmt;
    _HomeResumoCache.devolucoesFmt = _devolucoesHojeFmt;
    _HomeResumoCache.vendasMelhoraram = _vendasMelhoraram;
    _HomeResumoCache.lucroMelhorou = _lucroMelhorou;
    _HomeResumoCache.devolucoesPioraram = _devolucoesPioraram;
    _HomeResumoCache.dateKey = _todayKey();
    _HomeResumoCache.lastUpdated = DateTime.now();
  }

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _carregarEmpresas();
    // Removido auto refresh periódico
  }
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregarEmpresas() async {
    final service = CadLojasService(_apiClient);
    final empresas = await service.getEmpresasComNome();
    if (empresas.isNotEmpty && empresas.first.id != 0) {
      empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }

    // Atualiza estado com empresas e empresa selecionada
    setState(() {
      _empresas = empresas;
      _empresaSelecionada = empresas.firstWhere((e) => e.id == 0, orElse: () => empresas.first);
    });

    // Inicia o carregamento do resumo de vendas imediatamente após setar a empresa
    final hydrated = _hydrateFromSessionCacheIfValid();
    if (!hydrated) {
      _carregarResumoVendas();
    }
  }

  void _carregarResumoVendas() async {
    if (_empresaSelecionada == null) return;
    final myToken = ++_loadToken;
    final prefs = await SharedPreferences.getInstance();
    if (_empresaSelecionada!.id != 0) {
      final lastCacheTimeMillis = prefs.getInt(_cacheKeyResumoTimestamp(_empresaSelecionada!.id));
      if (lastCacheTimeMillis != null) {
        final lastCacheTime = DateTime.fromMillisecondsSinceEpoch(lastCacheTimeMillis);
        if (DateTime.now().difference(lastCacheTime) < cacheDuration) {
          setState(() {
            _totalVendaHojeFmt = prefs.getString(_cacheKeyTotalVenda(_empresaSelecionada!.id)) ?? 'R\$ 0,00';
            _lucroHojeFmt = prefs.getString(_cacheKeyLucro(_empresaSelecionada!.id)) ?? 'R\$ 0,00';
            _devolucoesHojeFmt = prefs.getString(_cacheKeyDevolucoes(_empresaSelecionada!.id)) ?? 'R\$ 0,00';
            _isLoadingResumo = false;
          });
          return;
        }
      }
    }
    if (_empresaSelecionada!.id == 0) {
      if (_hydrateFromSessionCacheIfValid()) return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingResumo = true;
    });

    final repo = FaturamentoComLucroRepository(_apiClient);

    final hoje = DateTime.now();
    final hojeInicio = DateTime(hoje.year, hoje.month, hoje.day);
    final hojeFim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);

    try {
      double totalVenda = 0.0;
      double lucro = 0.0;
      double devolucoes = 0.0;

      double totalVendaOntem = 0.0;
      double lucroOntem = 0.0;
      double devolucoesOntem = 0.0;

      _resumosPorEmpresa = <int, _ResumoEmpresa>{}; // limpa antes de preencher

      final ontem = hoje.subtract(Duration(days: 1));
      final ontemInicio = DateTime(ontem.year, ontem.month, ontem.day);
      final ontemFim = DateTime(ontem.year, ontem.month, ontem.day, 23, 59, 59);

      if (_empresaSelecionada!.id == 0) {
        // Todas as empresas: atualização incremental conforme cada empresa retorna
        final empresasValidas = _empresas.where((e) => e.id != 0).toList();

// Limpa estado parcial
        _resumosPorEmpresa = <int, _ResumoEmpresa>{};
        _hojePorEmpresa.clear();
        _ontemPorEmpresa.clear();

// Datas base
        final hoje = DateTime.now();
        final hojeInicioL = DateTime(hoje.year, hoje.month, hoje.day);
        final hojeFimL = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);
        final ontem = hoje.subtract(const Duration(days: 1));
        final ontemInicioL = DateTime(ontem.year, ontem.month, ontem.day);
        final ontemFimL = DateTime(ontem.year, ontem.month, ontem.day, 23, 59, 59);

// Controla concorrência simples (até 4 ao mesmo tempo)
        final queue = List<Empresa>.from(empresasValidas);
        int running = 0;
        const int maxConc = 4;

        Future<void> startNext() async {
          if (!mounted || myToken != _loadToken) return;
          if (queue.isEmpty) return;
          if (running >= maxConc) return;
          final emp = queue.removeAt(0);
          running++;
          try {
            // Busca hoje e ontem (usa cache em memória se existir)
            Future<List<FaturamentoComLucro>> fHoje() async {
              final mem = _getMem(emp.id, hojeInicioL);
              if (mem != null) return mem;
              final lista = await repo.getResumoFaturamentoComLucro(
                idEmpresa: emp.id,
                dataInicial: hojeInicioL,
                dataFinal: hojeFimL,
              );
              _putMem(emp.id, hojeInicioL, lista);
              return lista;
            }

            Future<List<FaturamentoComLucro>> fOntem() async {
              final mem = _getMem(emp.id, ontemInicioL);
              if (mem != null) return mem;
              final lista = await repo.getResumoFaturamentoComLucro(
                idEmpresa: emp.id,
                dataInicial: ontemInicioL,
                dataFinal: ontemFimL,
              );
              _putMem(emp.id, ontemInicioL, lista);
              return lista;
            }

            final results = await Future.wait([fHoje(), fOntem()]);
            if (!mounted || myToken != _loadToken) return;

            final hj = results[0];
            final on = results[1];

            final vH = hj.fold<double>(0.0, (s, e) => s + e.totalVenda);
            final lH = hj.fold<double>(0.0, (s, e) => s + e.lucro);
            final dH = hj.fold<double>(0.0, (s, e) => s + e.devolucoes);

            final vO = on.fold<double>(0.0, (s, e) => s + e.totalVenda);
            final lO = on.fold<double>(0.0, (s, e) => s + e.lucro);
            final dO = on.fold<double>(0.0, (s, e) => s + e.devolucoes);

            // Atualiza parciais e UI desta empresa
            final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
            _hojePorEmpresa[emp.id] = _BrutosEmpresa(vH, lH, dH);
            _ontemPorEmpresa[emp.id] = _BrutosEmpresa(vO, lO, dO);
            _resumosPorEmpresa[emp.id] = _ResumoEmpresa(
              totalFmt: currency.format(vH),
              lucroFmt: currency.format(lH),
              devolucoesFmt: currency.format(dH),
              vendasMelhoraram: vH > vO,
              lucroMelhorou: lH > lO,
              devolucoesPioraram: dH > dO,
            );

            // Recalcula totais gerais com base no que já chegou
            double totalVendaP = 0.0, lucroP = 0.0, devolP = 0.0;
            double totalVendaOntemP = 0.0, lucroOntemP = 0.0, devolOntemP = 0.0;
            for (final b in _hojePorEmpresa.values) {
              totalVendaP += b.total; lucroP += b.lucro; devolP += b.devol;
            }
            for (final b in _ontemPorEmpresa.values) {
              totalVendaOntemP += b.total; lucroOntemP += b.lucro; devolOntemP += b.devol;
            }

            if (!mounted || myToken != _loadToken) return;
            setState(() {
              _totalVendaHojeFmt = currency.format(totalVendaP);
              _lucroHojeFmt = currency.format(lucroP);
              _devolucoesHojeFmt = currency.format(devolP);
              _vendasMelhoraram = totalVendaP > totalVendaOntemP;
              _lucroMelhorou = lucroP > lucroOntemP;
              _devolucoesPioraram = devolP > devolOntemP;
              // Mantém o loader ativo até concluir TODAS as empresas
            });
            _saveSessionCacheFromState();
          } catch (_) {
            // ignora erro dessa empresa e segue
          } finally {
            running--;
            // Dispara próximos até esvaziar
            while (running < maxConc && queue.isNotEmpty) {
              await startNext();
            }
          }
        }

// Inicializa os primeiros
        while (running < maxConc && queue.isNotEmpty) {
          await startNext();
        }

// Aguarda finalizar todas internamente (a UI já está sendo atualizada)
        while (running > 0 || queue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (!mounted || myToken != _loadToken) return;
        }
        // 🔚 Agrega totais finais ao terminar e evita sobrescrita por zeros no setState final
        if (!mounted || myToken != _loadToken) return;
        double totalVendaP = 0.0, lucroP = 0.0, devolP = 0.0;
        double totalVendaOntemP = 0.0, lucroOntemP = 0.0, devolOntemP = 0.0;
        for (final b in _hojePorEmpresa.values) {
          totalVendaP += b.total; lucroP += b.lucro; devolP += b.devol;
        }
        for (final b in _ontemPorEmpresa.values) {
          totalVendaOntemP += b.total; lucroOntemP += b.lucro; devolOntemP += b.devol;
        }
        final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        setState(() {
          _totalVendaHojeFmt = currency.format(totalVendaP);
          _lucroHojeFmt = currency.format(lucroP);
          _devolucoesHojeFmt = currency.format(devolP);
          _vendasMelhoraram = totalVendaP > totalVendaOntemP;
          _lucroMelhorou = lucroP > lucroOntemP;
          _devolucoesPioraram = devolP > devolOntemP;
          _isLoadingResumo = false;
        });
        _saveSessionCacheFromState();
        return;
      } else {
        // Empresa única (comportamento atual)
        final resultados = await repo.getResumoFaturamentoComLucro(
          idEmpresa: _empresaSelecionada!.id,
          dataInicial: hojeInicio,
          dataFinal: hojeFim,
        );
        totalVenda = resultados.fold<double>(0.0, (sum, e) => sum + e.totalVenda);
        lucro = resultados.fold<double>(0.0, (sum, e) => sum + e.lucro);
        devolucoes = resultados.fold<double>(0.0, (sum, e) => sum + e.devolucoes);

        final resultadosOntem = await repo.getResumoFaturamentoComLucro(
          idEmpresa: _empresaSelecionada!.id,
          dataInicial: ontemInicio,
          dataFinal: ontemFim,
        );
        totalVendaOntem = resultadosOntem.fold<double>(0.0, (sum, e) => sum + e.totalVenda);
        lucroOntem = resultadosOntem.fold<double>(0.0, (sum, e) => sum + e.lucro);
        devolucoesOntem = resultadosOntem.fold<double>(0.0, (sum, e) => sum + e.devolucoes);

        _resumosPorEmpresa = <int, _ResumoEmpresa>{}; // não exibe lista por empresa no modo empresa única
      }

      if (!mounted || myToken != _loadToken) return;
      setState(() {
        _totalVendaHojeFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalVenda);
        _lucroHojeFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(lucro);
        _devolucoesHojeFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(devolucoes);
        _vendasMelhoraram = totalVenda > totalVendaOntem;
        _lucroMelhorou = lucro > lucroOntem;
        _devolucoesPioraram = devolucoes > devolucoesOntem;
        _isLoadingResumo = false;
      });
      if (_empresaSelecionada!.id != 0) {
        await prefs.setString(_cacheKeyTotalVenda(_empresaSelecionada!.id), _totalVendaHojeFmt);
        await prefs.setString(_cacheKeyLucro(_empresaSelecionada!.id), _lucroHojeFmt);
        await prefs.setString(_cacheKeyDevolucoes(_empresaSelecionada!.id), _devolucoesHojeFmt);
        await prefs.setInt(_cacheKeyResumoTimestamp(_empresaSelecionada!.id), DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      setState(() {
        _totalVendaHojeFmt = 'Erro';
        _lucroHojeFmt = 'Erro';
        _devolucoesHojeFmt = 'Erro';
        _isLoadingResumo = false;
      });
    }
  }

  Widget _buildResumoGeral() {
    return Column(
      children: [
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Faturamento Atual',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'As setas representam o faturamento de hoje comparado com ontem',
              waitDuration: const Duration(milliseconds: 500),
              child: const Icon(
                Icons.info_outline,
                size: 24,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: _isLoadingResumo
              ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Valor: $_totalVendaHojeFmt', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Icon(
                          _vendasMelhoraram ? Icons.arrow_upward : Icons.arrow_downward,
                          color: _vendasMelhoraram ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Lucro: $_lucroHojeFmt', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Icon(
                          _lucroMelhorou ? Icons.arrow_upward : Icons.arrow_downward,
                          color: _lucroMelhorou ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Devoluções: $_devolucoesHojeFmt', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Icon(
                          _devolucoesPioraram ? Icons.arrow_upward : Icons.arrow_downward,
                          color: _devolucoesPioraram ? Colors.red : Colors.green,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const MainDrawer(),
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          setState(() {
            _autoRefreshAtivo = false;
          });
        }
      },
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          FutureBuilder<DateTime?>(
            future: getAccessGrantedAt(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return SizedBox.shrink();
              final accessGrantedAt = snapshot.data!;
              return Tooltip(
                message: () {
                  final grantedDate = accessGrantedAt;
                  final vencimentoReal = grantedDate.add(Duration(days: 30));
                  final vencimentoComTolerancia = grantedDate.add(Duration(days: 37));
                  final agora = DateTime.now();

                  if (agora.isBefore(vencimentoReal)) {
                    return 'Mensalidade válida até: ${DateFormat('dd/MM/yyyy').format(vencimentoReal)}.';
                  } else if (agora.isBefore(vencimentoComTolerancia)) {
                    return 'Mensalidade vencida em: ${DateFormat('dd/MM/yyyy').format(vencimentoReal)}. Seu acesso será bloqueado logo.';
                  } else {
                    return 'Mensalidade vencida. Acesso bloqueado.';
                  }
                }(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Icon(Icons.info_outline, color: Colors.black26,),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/login/logo.png',
                        height: 100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        "Analyze",
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                          letterSpacing: 0.8,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: PopupMenuButton<Empresa>(
                    color: Colors.white,
                    itemBuilder: (context) {
                      return _empresas.map((empresa) {
                        return PopupMenuItem<Empresa>(
                          value: empresa,
                          child: Text(empresa.nome),
                        );
                      }).toList();
                    },
                    onSelected: (empresa) {
                      setState(() {
                        _empresaSelecionada = empresa;
                      });
                      _carregarResumoVendas();
                    },
                    tooltip: 'Selecionar empresa',
                    child: TextButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                      label: Text(
                        _empresaSelecionada?.nome ?? 'Empresa',
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

                // Quando "Todas as Empresas" estiver selecionado, mostra o totalizador no topo e a lista abaixo
                if ((_empresaSelecionada?.id ?? -1) == 0) ...[
                  // Totalizador geral no topo (abaixo dos filtros)
                  _buildResumoGeral(),
                  const SizedBox(height: 12),

                  const SizedBox(height: 8),
                  ListView.builder(
                    itemCount: _empresas.where((e) => e.id != 0).length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final empresasSemTodas = _empresas.where((e) => e.id != 0).toList();
                      final emp = empresasSemTodas[index];
                      final resumo = _resumosPorEmpresa[emp.id];
                      return GestureDetector(
                        onTap: () {
                          final hoje = DateTime.now();
                          final inicio = DateTime(hoje.year, hoje.month, hoje.day);
                          final fim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VendasPage(
                                empresasPreSelecionadas: [emp],
                                intervaloPreSelecionado: DateTimeRange(start: inicio, end: fim),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.09),
                                blurRadius: 8,
                                spreadRadius: 0.5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Center(child: Text(emp.nome, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                              const SizedBox(height: 8),
                              // ... resto do conteúdo do card
                              if (resumo == null)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: LinearProgressIndicator(minHeight: 2),
                                )
                              else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Valor: ${resumo.totalFmt}', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Icon(
                                      resumo.vendasMelhoraram ? Icons.arrow_upward : Icons.arrow_downward,
                                      color: resumo.vendasMelhoraram ? Colors.green : Colors.red,
                                      size: 16,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Lucro: ${resumo.lucroFmt}', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Icon(
                                      resumo.lucroMelhorou ? Icons.arrow_upward : Icons.arrow_downward,
                                      color: resumo.lucroMelhorou ? Colors.green : Colors.red,
                                      size: 16,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Devoluções: ${resumo.devolucoesFmt}', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Icon(
                                      resumo.devolucoesPioraram ? Icons.arrow_upward : Icons.arrow_downward,
                                      color: resumo.devolucoesPioraram ? Colors.red : Colors.green,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // Modo empresa única: mantém o bloco original aqui
                  _buildResumoGeral(),
                ],
                const SizedBox(height: 100),
                // const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Visibility(
        visible: !_isLoadingResumo,
        child: GestureDetector(
          onTap: () async {
            // (reuse same onTap logic as the removed card)
            final abrir = await showDialog<bool>(
              context: context,
              builder: (context) => Dialog(
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
                      const Text(
                        'Você será redirecionado para fora do app, ao Google Forms.\nDeseja continuar?',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: const Color(0xFF2E7D32),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Sim',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            if (abrir == true) {
              final uri = Uri.parse('https://forms.gle/wxKd6P1cYw6keZZU6');
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o link')),
                  );
                }
              }
            }
          },
          child: Builder(
            builder: (context) {
              final double screenW = MediaQuery.of(context).size.width;
              // Mesma largura visual do conteúdo: (tela - 32 de padding) limitado a 400
              final double width = (screenW - 32).clamp(0, 400).toDouble();

              return SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.09),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.lightbulb_outline, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min, // evita “esticar” verticalmente
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Sugestão de Indicador?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('Envie clicando aqui.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  final String texto;

  const _AlertaCard({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
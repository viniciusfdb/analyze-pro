import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';

// === NOVO IMPORT 22-06-2025: cache da tela Metas
import 'package:analyzepro/services/caches/metas_page_cache.dart';

import 'package:analyzepro/repositories/vendas/faturamento_com_lucro_repository.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import 'package:analyzepro/models/metas/CadMeta.dart';

import '../../../repositories/metas/cad_meta_repository.dart';
import '../../home/menu_principal_page.dart';

class MetasPorEmpresaPage extends StatefulWidget {
  const MetasPorEmpresaPage({Key? key}) : super(key: key);

  @override
  _MetasPorEmpresaPageState createState() => _MetasPorEmpresaPageState();
}

// === ALTERAÇÃO 22-06-2025: adiciona WidgetsBindingObserver
class _MetasPorEmpresaPageState extends State<MetasPorEmpresaPage> with WidgetsBindingObserver {
  final _metaRepo = CadMetaRepository(ApiClient(AuthService()));
  final _fatRepo  = FaturamentoComLucroRepository(ApiClient(AuthService()));
  final _lojasSvc = CadLojasService(ApiClient(AuthService()));

  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoMedioEstimado;

  Timer? _cronometroTimer;
  double _cronometro = 0.0;

  bool _loading = true;
  String? _error;

  Map<int, bool> _loadStatus = {};

  // === CONTROLE GLOBAL 26‑06‑2025 ===
  static Future<void>? _globalFuture;
  // Início da consulta global – mantém cronômetro ativo entre instâncias
  static DateTime? _globalConsultaInicio;

  // Filtros da última busca ativa
  static String? _lastMesSelecionado;

  // Map compartilhado: idempresa → carregado?
  static final Map<int, bool> _sharedLoadStatus = {};
  // Empresas já conhecidas durante carregamento global
  static final Map<int, String> _sharedEmpresas = {};
  // Dados já carregados que precisam ser visíveis em novas instâncias
  static final Map<int, double> _sharedMetasTotal     = {};
  static final Map<int, double> _sharedFaturamentos   = {};

  // Mostra se ainda há alguma empresa pendente
  bool get _isLoading => _sharedLoadStatus.values.any((v) => v == false);


  late final List<String> _mesesDisponiveis;
  late String _mesSelecionado;

  DateTime get _dtInicio {
    final parts = _mesSelecionado.split('/');
    final month = int.parse(parts[0]);
    final year = int.parse(parts[1]);
    return DateTime(year, month, 1);
  }
  DateTime get _dtFim {
    final start = _dtInicio;
    final nextMonth = (start.month < 12)
        ? DateTime(start.year, start.month + 1, 1)
        : DateTime(start.year + 1, 1, 1);
    return nextMonth.subtract(const Duration(seconds: 1));
  }

  Map<int, String> _empresas = {};            // idempresa → nomefantasia
  Map<int, List<CadMeta>> _metas = {};        // idempresa → lista de metas
  Map<int, double> _faturamentos = {};        // idempresa → total faturado no período
  Map<int, double> totalPorEmpresa = {};      // idempresa → soma metas deduplicadas

  /// Inicia ou reinicia o cronômetro visual baseado em [_globalConsultaInicio].
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsedMs =
          DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() => _cronometro = elapsedMs / 1000);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tempoRepo = TempoExecucaoRepository();
    final now = DateTime.now();
    _mesesDisponiveis = List.generate(12, (i) {
      final dt = DateTime(now.year, now.month - i);
      return DateFormat('MM/yyyy').format(dt);
    });

    // === 27‑06‑2025: mantém último filtro se existir ===
    if (_lastMesSelecionado != null &&
        _mesesDisponiveis.contains(_lastMesSelecionado)) {
      _mesSelecionado = _lastMesSelecionado!;
    } else {
      _mesSelecionado = _mesesDisponiveis.first;
    }
    _loadAll();
  }

  Future<void> _loadAll() async {
    final fmtMoney = NumberFormat.simpleCurrency(locale: 'pt_BR');
    // Exibe tempo médio estimado antes de qualquer carregamento
    final tempoMedio = await _tempoRepo.buscarTempoMedio('metas');

    // Se o mês mudou desde a última consulta, limpa caches e mapas locais/compartilhados
    final bool periodoMudou = (_lastMesSelecionado != null && _lastMesSelecionado != _mesSelecionado);
    if (periodoMudou) {
      _sharedMetasTotal.clear();
      _sharedFaturamentos.clear();
      _sharedEmpresas.clear();
      _sharedLoadStatus.clear();

      _empresas.clear();
      _metas.clear();
      _faturamentos.clear();
      totalPorEmpresa.clear();
      _loadStatus.clear();
    }

    if (mounted) {
      setState(() {
        _tempoMedioEstimado = tempoMedio;
        _loading = true;
        _error = null;
      });
    }
    // Se já existe cache válido para o mês atual e nenhuma requisição global em andamento,
    // usa o cache e encerra imediatamente.
    if (_globalFuture == null &&
        MetasPageCache.instance.cacheValido &&
        MetasPageCache.instance.mesSelecionado == _mesSelecionado) {
      // Zera cronômetro — não há consulta em andamento
      _cronometroTimer?.cancel();
      _globalConsultaInicio = null;
      _cronometro = 0.0;

      // Restaura dados do cache
      _empresas        = Map<int, String>.from(MetasPageCache.instance.empresas);
      totalPorEmpresa  = Map<int, double>.from(MetasPageCache.instance.metasTotais);
      _faturamentos    = Map<int, double>.from(MetasPageCache.instance.faturamentos);

      // Todos os loaders concluídos
      _sharedLoadStatus
        ..clear()
        ..addEntries(_empresas.keys.map((id) => MapEntry(id, true)));
      _loadStatus = Map<int, bool>.from(_sharedLoadStatus);

      if (mounted) {
        setState(() {
          _loading = false;
          _tempoMedioEstimado = tempoMedio;
        });
      }
      await _inicializarTempoExecucao(); // garante tempo médio visível ao restaurar cache
      return;
    }
    // Só inicia cronômetro se realmente vamos consultar a API
    final bool precisaConsultar =
        !MetasPageCache.instance.cacheValido ||
        MetasPageCache.instance.mesSelecionado != _mesSelecionado ||
        _globalFuture != null;

    if (precisaConsultar && _globalFuture == null) {
      // Nova consulta: reinicia cronômetro
      _cronometro = 0.0;
      _globalConsultaInicio = DateTime.now();
      _startCronometro();
    } else if (_globalFuture != null) {
      // Já existe consulta em andamento: garante cronômetro ativo
      _startCronometro();
    } else {
      // Nenhuma consulta; só cache — zera cronômetro
      _cronometroTimer?.cancel();
      _globalConsultaInicio = null;
      _cronometro = 0.0;
    }
    _lastMesSelecionado = _mesSelecionado;
    if (_globalFuture != null) {
      // Mostrar loaders apenas para EMPRESAS que ainda não terminaram
      if (_empresas.isEmpty && _sharedEmpresas.isNotEmpty) {
        _empresas = Map<int, String>.from(_sharedEmpresas);
      } else if (_empresas.isEmpty && MetasPageCache.instance.cacheValido) {
        _empresas = Map<int, String>.from(MetasPageCache.instance.empresas);
      }

      // Copia progresso já alcançado
      _loadStatus = Map<int,bool>.from(_sharedLoadStatus);
      // garante que loaders concluídos não sejam revertidos para falso
      _loadStatus.updateAll((id, val) => _sharedLoadStatus[id] ?? val);
      // Copia metas e faturamentos parciais já disponíveis
      totalPorEmpresa = Map<int, double>.from(_sharedMetasTotal);
      _faturamentos   = Map<int, double>.from(_sharedFaturamentos);
      if (mounted) setState(() {});

      // Aguarda a futura global
      await _globalFuture!;

      await _inicializarTempoExecucao();

      // garante que shared map esteja totalmente true
      _sharedLoadStatus.updateAll((key, value) => true);

      // Após a conclusão, popula dados vindos do cache atualizado e marca como carregado
      if (MetasPageCache.instance.cacheValido) {
        _empresas       = Map<int, String>.from(MetasPageCache.instance.empresas);
        totalPorEmpresa = Map<int, double>.from(MetasPageCache.instance.metasTotais);
        _faturamentos   = Map<int, double>.from(MetasPageCache.instance.faturamentos);
        _loadStatus     = Map<int,bool>.from(_sharedLoadStatus);
      }

      if (mounted) {
        setState(() { _loading = false; });
      }
      return;
    }
    _globalFuture = () async {
      final stopwatch = Stopwatch()..start();
      try {
        // === VERIFICA CACHE 22-06-2025 ===
        if (MetasPageCache.instance.cacheValido &&
            MetasPageCache.instance.mesSelecionado == _mesSelecionado) {
          // Usando cache completo – zera cronômetro e cancela timer
          _cronometroTimer?.cancel();
          _globalConsultaInicio = null;
          _cronometro = 0.0;

          _empresas        = Map<int, String>.from(MetasPageCache.instance.empresas);
          totalPorEmpresa  = Map<int, double>.from(MetasPageCache.instance.metasTotais);
          _faturamentos    = Map<int, double>.from(MetasPageCache.instance.faturamentos);

          // Todos os dados já estão em cache ⇒ loaders devem estar completos
          _sharedLoadStatus
            ..clear()
            ..addEntries(_empresas.keys.map((id) => MapEntry(id, true)));
          _loadStatus = Map<int, bool>.from(_sharedLoadStatus);

          if (mounted) {
            setState(() { _loading = false; });
            // Mantém tempo médio na tela
            _tempoMedioEstimado = tempoMedio;
          }
          return;
        }

        // 1) buscar empresas
        final empresas = await _lojasSvc.getEmpresasComNome();
        // Mapa temporário de todas as empresas retornadas
        final Map<int, String> empresasMap =
            {for (var e in empresas) e.id: e.nome};
        // Ainda não atualizamos _empresas/UI – aguardaremos as metas

        // 2) buscar metas e somar por empresa
        final metas = await _metaRepo.fetchAll(
          dtInicio: _dtInicio,
          dtFim:    _dtFim,
        );

        totalPorEmpresa.clear();
        for (var m in metas) {
          totalPorEmpresa[m.idempresa] = (totalPorEmpresa[m.idempresa] ?? 0) + m.metavlrvenda;
        }
        // Atualiza compartilhado de metas totais
        _sharedMetasTotal
          ..clear()
          ..addAll(totalPorEmpresa);

        // Mantém somente empresas com meta > 0
        _empresas = {
          for (var id in totalPorEmpresa.keys)
            if (totalPorEmpresa[id]! > 0) id: empresasMap[id]!
        };

        // Atualiza shared maps apenas com empresas relevantes
        _sharedEmpresas
          ..clear()
          ..addAll(_empresas);

        _sharedLoadStatus
          ..clear()
          ..addEntries(_empresas.keys.map((id) => MapEntry(id, false)));

        if (mounted) {
          _loadStatus = Map<int, bool>.from(_sharedLoadStatus);
          setState(() {}); // exibe loaders apenas para empresas válidas
        }

        // 3) para cada empresa, buscar faturamento no mesmo período
        _faturamentos.clear();
        for (final idEmp in totalPorEmpresa.keys) {
          final resumo = await _fatRepo.getResumoFaturamentoComLucro(
            idEmpresa:  idEmp,
            dataInicial: _dtInicio,
            dataFinal:   _dtFim,
          );
          final total = resumo.fold<double>(
              0.0, (sum, item) => sum + item.totalVenda
          );
          _faturamentos[idEmp] = total;
          // Preenche compartilhado de faturamentos
          _sharedFaturamentos[idEmp] = total;
          _sharedLoadStatus[idEmp] = true;
          if (mounted) {
            _loadStatus[idEmp] = true;
            setState(() {});
          }
          final totalMeta = totalPorEmpresa[idEmp] ?? 0.0;
          print('🚀 Empresa $idEmp - Faturamento: ${fmtMoney.format(total)} - Meta: ${fmtMoney.format(totalMeta)}');
        }
        // === 28‑06‑2025: garante que empresas sem meta também sejam marcadas como concluídas
        for (final id in _empresas.keys) {
          _sharedLoadStatus[id] = true;
          _loadStatus[id] = true;
        }
        // === SALVA CACHE 22-06-2025 ===
        MetasPageCache.instance.salvar(
          mesSelecionado: _mesSelecionado,
          empresas: _empresas,
          metasTotais: totalPorEmpresa,
          faturamentos: _faturamentos,
        );
      } catch (e) {
        _error = e.toString();
      } finally {
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        final tempoMs = stopwatch.elapsedMilliseconds;

        // Avalia cache ANTES de zerar os mapas
        final cacheDetectado = _sharedMetasTotal.isEmpty ||
            _sharedMetasTotal.values.every((v) => v == 0.0);

        _sharedMetasTotal.clear();
        _sharedFaturamentos.clear();
        _sharedEmpresas.clear();
        _sharedLoadStatus.updateAll((key, value) => true);

        _globalFuture  = null;
        const chave = 'metas';
        if (cacheDetectado) {
          debugPrint('⏱️ Cache detectado – não atualizar tempo médio');
        } else {
          debugPrint('💾 Salvando tempo médio real de execução: ${tempoMs}ms');
          await _tempoRepo.salvarTempo(chave, tempoMs);
        }
        final media = await _tempoRepo.buscarTempoMedio(chave);
        if (mounted) {
          setState(() {
            _tempoMedioEstimado = media;
          });
        }
        if (mounted) {
          setState(() { _loading = false; });
        }
      }
    }();

    await _globalFuture!;
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresas.isEmpty) return;
    const chave = 'metas';
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoMedioEstimado = media;
      });
    }
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
    final fmtMoney = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
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
      drawer: const MainDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate.fixed([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    PopupMenuButton<String>(
                      color: Colors.white,
                      initialValue: _mesSelecionado,
                      onSelected: (value) {
                        setState(() {
                          _mesSelecionado = value;
                        });
                        _loadAll();
                      },
                      itemBuilder: (context) => _mesesDisponiveis
                          .map((mes) => PopupMenuItem(
                                value: mes,
                                child: Text(mes),
                              ))
                          .toList(),
                      child: IgnorePointer(
                        ignoring: _isLoading,
                        child: Opacity(
                          opacity: _isLoading ? 0.5 : 1.0,
                          child: TextButton(
                            onPressed: null,
                            child: Text(
                              _mesSelecionado,
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
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Metas por Empresa',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: '  ${_cronometro.toStringAsFixed(1)}s',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
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
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Erro: $_error'),
                )
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_empresas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Nenhuma meta encontrada para este período',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              else
                ..._empresas.keys.map((idEmp) {
                  final nome = _empresas[idEmp] ?? 'Empresa $idEmp';
                  final loaded = _loadStatus[idEmp] ?? false;

                  if (!loaded) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(nome, style: const TextStyle(fontSize: 16))),
                          const SizedBox(width: 8),
                          const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                    );
                  }

                  final totalMeta = totalPorEmpresa[idEmp] ?? 0.0;
                  final fatu = _faturamentos[idEmp] ?? 0.0;
                  if (totalMeta == 0.0 && fatu == 0.0) return const SizedBox.shrink();
                  final percent = totalMeta > 0 ? (fatu / totalMeta) : 0.0;
                  final percentLabel = '${(percent * 100).toStringAsFixed(0)}%';

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Stack(
                          children: [
                            Container(
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            Container(
                              height: 28,
                              width: MediaQuery.of(context).size.width * percent,
                              decoration: BoxDecoration(
                                color: _getCorMeta(percent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            Positioned.fill(
                              child: Center(
                                child: Text(
                                  fmtMoney.format(fatu),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Meta: ${fmtMoney.format(totalMeta)}'),
                            Text(
                              percentLabel,
                              style: TextStyle(
                                color: _getCorMeta(percent),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Legenda:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildLegendaCor(Colors.red, 'Menos de 50%'),
                        _buildLegendaCor(Colors.orange, '50% a 74%'),
                        _buildLegendaCor(Colors.blue, '75% a 99%'),
                        _buildLegendaCor(Colors.green, '100% a 119%'),
                        _buildLegendaCor(Colors.deepPurple, 'Mais de 120%'),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
  // Utilitário para definir cor da meta com base no percentual
  Color _getCorMeta(double percentual) {
    if (percentual < 0.5) {
      return Colors.red;
    } else if (percentual < 0.75) {
      return Colors.orange;
    } else if (percentual < 1.0) {
      return Colors.blue;
    } else if (percentual < 1.2) {
      return Colors.green;
    } else {
      return Colors.deepPurple;
    }
  }

  // === LIMPA OBSERVER 22-06-2025 ===
  @override
  void dispose() {
    _cronometroTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

}

// Método auxiliar para legenda de cores
Widget _buildLegendaCor(Color cor, String label) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: cor,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
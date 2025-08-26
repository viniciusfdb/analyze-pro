import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl.dart' show toBeginningOfSentenceCase;
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/models/vendas/faturamento_com_lucro_model.dart';
import 'package:analyzepro/repositories/vendas/faturamento_com_lucro_repository.dart';
import '../../../models/vendas/empresa_colaborador.dart';
import '../../../repositories/cronometro/tempo_execucao_repository.dart';
import '../../../repositories/vendas/empresa_colaborador_repository.dart';
import '../../../services/caches/empresa_colaborador_page_cache.dart';
import '../../home/menu_principal_page.dart';

class EmpresaColaboradorPage extends StatefulWidget {
  const EmpresaColaboradorPage({super.key});
  @override
  State<EmpresaColaboradorPage> createState() => _EmpresaColaboradorPageState();
}

class _EmpresaColaboradorPageState extends State<EmpresaColaboradorPage> with WidgetsBindingObserver {

  // Campos estáticos para armazenar filtros anteriores
  static Empresa? _lastEmpresaSelecionada;
  static int? _lastAno;
  static int? _lastMes;

  // Controle global de consulta e tempo
  static Future<void>? _globalFuture;
  static DateTime? _globalConsultaInicio;
  static List<EmpresaResumoCacheEntry>? _lastResumos;
  static FaturamentoComLucro? _lastFaturamento;
  static EmpresaColaborador? _lastColaborador;
  static int? _lastQtdManual;
  // Mantém a última estimativa de tempo médio entre hot‑reloads
  static double? _lastTempoMedioEstimado;
  double? _tempoExecucao;
  double? _tempoMedioEstimado;
  Color _corPorValor(double valor) {
    if (valor <= 25000) return Colors.red;
    if (valor <= 30000) return Colors.orange;
    if (valor <= 35000) return Colors.green;
    return Colors.blue;
  }
  late final AuthService _auth;
  late final ApiClient _api;
  late final CadLojasService _lojasService;
  late final EmpresaColaboradorRepository _colabRepo;
  late final FaturamentoComLucroRepository _fatRepo;

  List<Empresa> _empresas = [];
  // Controle de carregamento de empresas (idEmpresa -> carregado)
  final Map<int, bool> _empresasCarregadas = {};
  Empresa? _empresaSelecionada;
  int _ano = DateTime.now().year;
  int _mes = DateTime.now().month;

  bool _loading = false;
  double _cronometro = 0.0;
  Timer? _cronometroTimer;

  FaturamentoComLucro? _faturamento;
  EmpresaColaborador? _colaborador;
  int? _qtdManual;

  List<_EmpresaResumo> _resumos = [];
  // controla modo de exibição (Totais × Por Colaborador)
  bool _porColaborador = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = AuthService();
    _api = ApiClient(_auth);
    _lojasService = CadLojasService(_api);
    _colabRepo = EmpresaColaboradorRepository(_api);
    _fatRepo = FaturamentoComLucroRepository(_api);

    // --- RESTAURA FILTROS DO CACHE ---
    final cache = EmpresaColaboradorPageCache.instance;
    _empresaSelecionada = cache.empresaSelecionada;
    _ano = cache.ano ?? _ano;
    _mes = cache.mes ?? _mes;
    // --- RESTAURA TEMPO MÉDIO ESTIMADO IMEDIATAMENTE DO CACHE, ANTES DE QUALQUER setState ---
    _tempoMedioEstimado = cache.tempoMedioEstimado;
    _lastTempoMedioEstimado = _tempoMedioEstimado;
    // Força exibição imediata do histórico mesmo após hot reload
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final empresasDisponiveis = await _lojasService.getEmpresasComNome();
      final empresasParaCalculo = _empresaSelecionada?.id == 0
          ? empresasDisponiveis.where((e) => e.id != 0).map((e) => e.id).join(",")
          : '${_empresaSelecionada?.id}';

      final dias = DateTime(_ano, _mes + 1, 0).difference(DateTime(_ano, _mes, 1)).inDays;
      final chave = '$empresasParaCalculo|$dias';
      final tempo = await TempoExecucaoRepository().buscarTempoMedio(chave);
      if (tempo != null && mounted) {
        setState(() => _tempoMedioEstimado = tempo);
      }
    });

    // Se o cache está válido e nenhuma consulta global está ativa, usa cache e retorna imediatamente
    if (cache.cacheValido && _globalFuture == null) {
      setState(() {
        _resumos = cache.resumos!.map((r) => _EmpresaResumo(
          empresa: r.empresa,
          colaboradores: r.colaboradores,
          fat: r.fat,
        )).toList();
        _faturamento = cache.faturamento;
        _colaborador = cache.colaborador;
        _qtdManual = cache.qtdManual;
        _tempoMedioEstimado = cache.tempoMedioEstimado;
        _loading = false;
      });

      // ⚡️ Garante rebuild para exibir estimativa imediatamente após hot reload com cache válido
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {});
        });
      }

      // ⚠️ Garante que todas as empresas sejam carregadas corretamente do serviço
      _carregarEmpresas();
      return;
    }

    _carregarEmpresas().then((_) {
      if (_globalFuture != null) {
        final cache = EmpresaColaboradorPageCache.instance;
        _empresaSelecionada = cache.empresaSelecionada ?? _empresaSelecionada;
        _ano = cache.ano ?? _ano;
        _mes = cache.mes ?? _mes;
        _lastEmpresaSelecionada = _empresaSelecionada;
        _lastAno = _ano;
        _lastMes = _mes;
        _loading = true;
        _startCronometro();

        _globalFuture!.then((_) {
          if (mounted) {
            setState(() {
              _resumos = _lastResumos!
                  .map((r) => _EmpresaResumo(
                        empresa: r.empresa,
                        colaboradores: r.colaboradores,
                        fat: r.fat,
                      ))
                  .toList();
              _faturamento = _lastFaturamento;
              _colaborador = _lastColaborador;
              _qtdManual = _lastQtdManual;
              _empresaSelecionada = _lastEmpresaSelecionada;
              _ano = _lastAno ?? _ano;
              _mes = _lastMes ?? _mes;
              _loading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        });
        // Não precisa buscar tempo médio estimado novamente, já buscado centralizado acima
        _empresaSelecionada ??= _lastEmpresaSelecionada;
        _ano = _lastAno ?? DateTime.now().year;
        _mes = _lastMes ?? DateTime.now().month;
        _loading = true;
        _globalFuture!.then((_) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
        });
      }

      if (_empresaSelecionada != null && _globalFuture == null) {
        setState(() {
          _empresas = _empresas;
        });
        _iniciarConsulta();
      }
    });
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

  // Atualiza quantidade de colaboradores e refaz cálculo dos indicadores
  void _atualizarColab(Empresa emp, int novoValor) {
    setState(() {
      final idx = _resumos.indexWhere((e) => e.empresa.id == emp.id);
      if (idx != -1) {
        final antigo = _resumos[idx];
        _resumos[idx] = _EmpresaResumo(
          empresa: antigo.empresa,
          colaboradores: novoValor,
          fat: antigo.fat,
        );
      }
      // Atualiza _lastResumos com os valores atualizados
      _lastResumos = _resumos.map((r) => EmpresaResumoCacheEntry(
        empresa: r.empresa,
        colaboradores: r.colaboradores,
        fat: r.fat,
      )).toList();
    });
  }

  Future<void> _carregarEmpresas() async {
    final emps = await _lojasService.getEmpresasComNome();
    // Garante que "Todas as Empresas" está presente
    if (emps.isNotEmpty && emps.first.id != 0) {
      emps.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }
    setState(() {
      _empresas = emps;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    _lastEmpresaSelecionada = _empresaSelecionada;
    // Restaura empresa selecionada do cache se não houver seleção
    if (_empresaSelecionada == null) {
      _empresaSelecionada = EmpresaColaboradorPageCache.instance.empresaSelecionada ?? _empresaSelecionada;
    }
    // Define empresa padrão somente se não tiver nenhuma seleção anterior
    final restoredEmpresa = _empresaSelecionada;
    setState(() {
      if (_globalFuture != null) {
        _empresaSelecionada = _lastEmpresaSelecionada ?? restoredEmpresa;
      } else {
        _empresaSelecionada = restoredEmpresa != null
            ? emps.firstWhere((e) => e.id == restoredEmpresa.id, orElse: () => Empresa(id: 0, nome: 'Todas as Empresas'))
            : Empresa(id: 0, nome: 'Todas as Empresas');
      }
    });
    // Só inicia consulta se não for continuação de consulta anterior
    if (_globalFuture == null) {
      // --- RESTAURA DO CACHE SE VÁLIDO ---
      final cache = EmpresaColaboradorPageCache.instance;
      _tempoMedioEstimado = cache.tempoMedioEstimado; // já restaurado centralmente no initState
      if (cache.cacheValido) {
        // --- Adiciona lógica para buscar tempo médio estimado do histórico do cronômetro imediatamente ---
        final dias = DateTime(_ano, _mes + 1, 0).difference(DateTime(_ano, _mes, 1)).inDays;
        final chave = '${cache.empresaSelecionada?.id == 0
            ? (cache.resumos?.isNotEmpty == true
                ? cache.resumos!.map((e) => e.empresa.id).join(",")
                : "0")
            : cache.empresaSelecionada?.id}|$dias';
        TempoExecucaoRepository().buscarTempoMedio(chave).then((tempo) {
          if (tempo != null && mounted) {
            setState(() => _tempoMedioEstimado = tempo);
          }
        });

        setState(() {
          _empresaSelecionada = cache.empresaSelecionada;
          _ano = cache.ano ?? _ano;
          _mes = cache.mes ?? _mes;
          _resumos = cache.resumos!.map((r) => _EmpresaResumo(
            empresa: r.empresa,
            colaboradores: r.colaboradores,
            fat: r.fat,
          )).toList();
          _faturamento = cache.faturamento;
          _colaborador = cache.colaborador;
          _qtdManual = cache.qtdManual;
          _tempoMedioEstimado = cache.tempoMedioEstimado;
          _loading = false;
        });
        // Não busca tempo médio estimado novamente aqui, já feito centralmente no initState
        return;
      }
      // Garante novamente "Todas as Empresas" no início antes de setState final (caso algum fluxo altere emps)
      if (emps.isNotEmpty && emps.first.id != 0) {
        emps.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
      }
      setState(() {
        _empresas = emps;
      });
      _iniciarConsulta();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {}); // ✅ Garante rebuild mesmo com filtros ativos
      });
      // --- SALVA NO CACHE PARA REAPROVEITAR AO RETORNAR À TELA ---
      EmpresaColaboradorPageCache.instance.salvar(
        resumos: _resumos.map((r) => EmpresaResumoCacheEntry(
          empresa: r.empresa,
          colaboradores: r.colaboradores,
          fat: r.fat,
        )).toList(),
        faturamento: _faturamento,
        colaborador: _colaborador,
        qtdManual: _qtdManual,
        empresaSelecionada: _empresaSelecionada,
        ano: _ano,
        mes: _mes,
        tempoMedioEstimado: _tempoMedioEstimado,
      );
    }
    // Se uma chamada anterior ainda estiver em andamento, não reinicia filtros, mas garante desbloqueio visual ao final
    if (_globalFuture != null) {
      _startCronometro();
      _globalFuture!.then((_) {
        if (mounted) {
          setState(() {
            _loading = false; // ✅ Garante desbloqueio visual
          });
        }
      });
    }
  }

  void _iniciarConsulta() async {
    if (_empresaSelecionada == null) return;
    if (_globalFuture == null) {
      _globalFuture = _iniciarConsultaInterna();
    }
    await _globalFuture;
    _globalFuture = null;
  }

  Future<void> _iniciarConsultaInterna() async {
    if (_globalFuture != null) return;
    if (_empresaSelecionada == null) return;
    setState(() {
      _loading = true;
      _cronometro = 0;
    });
    _cronometroTimer?.cancel();
    // Marca início global
    _globalConsultaInicio = DateTime.now();
    _startCronometro();

    final dataInicial = DateTime(_ano, _mes, 1);
    final dataFinal = DateTime(_ano, _mes + 1, 0);

    // Verifica se é "Todas as Empresas"
    final empresasParaConsultar = _empresaSelecionada!.id == 0
        ? _empresas.where((e) => e.id != 0).toList()
        : [_empresaSelecionada!];

    // Inicializa controle de carregamento
    _empresasCarregadas.clear();
    for (final emp in empresasParaConsultar) {
      _empresasCarregadas[emp.id] = false;
    }

    List<_EmpresaResumo> resultados = [];
    final stopwatch = Stopwatch()..start();

    for (final emp in empresasParaConsultar) {
      final fatList = await _fatRepo.getResumoFaturamentoComLucro(
        idEmpresa: emp.id,
        dataInicial: dataInicial,
        dataFinal: dataFinal,
      );

      double totalVenda = 0, lucro = 0, totalVendaBruta = 0, lucroBruto = 0, devolucoes = 0, ticketMedio = 0;
      int nroVendas = 0;
      final tickets = <double>[];

      for (final fat in fatList) {
        totalVenda += fat.totalVenda;
        lucro += fat.lucro;
        totalVendaBruta += fat.totalVendaBruta;
        lucroBruto += fat.lucroBruto;
        devolucoes += fat.devolucoes;
        nroVendas += fat.nroVendas;
        tickets.add(fat.ticketMedio);
      }

      ticketMedio = tickets.isNotEmpty ? tickets.reduce((a, b) => a + b) / tickets.length : 0.0;

      final colabs = await _colabRepo.getColaboradoresPorEmpresaAnoMes(
        idEmpresa: emp.id,
        ano: _ano,
        mes: _mes,
      );

      final qtdColab = colabs.isNotEmpty ? colabs.first.numcolaboradores : 0;

      resultados.add(_EmpresaResumo(
        empresa: emp,
        colaboradores: qtdColab,
        fat: fatList.isNotEmpty
            ? FaturamentoComLucro(
          idEmpresa: emp.id,
          dtMovimento: dataInicial,
          totalVenda: totalVenda,
          lucro: lucro,
          totalVendaBruta: totalVendaBruta,
          lucroBruto: lucroBruto,
          devolucoes: devolucoes,
          nroVendas: nroVendas,
          ticketMedio: ticketMedio,
        )
            : null,
      ));
      setState(() {
        _empresasCarregadas[emp.id] = true;
      });
    }

    stopwatch.stop();
    // Após a consulta, grava tempo e busca estimativa
    final tempoMs = stopwatch.elapsedMilliseconds;
    final tempoReal = tempoMs / 1000;
    final dias = dataFinal.difference(dataInicial).inDays;
    final chave = empresasParaConsultar.length == 1
        ? '${empresasParaConsultar.first.id}|$dias'
        : '0|$dias';
    _tempoExecucao = tempoReal;
    try {
      // TempoExecucaoRepository pode não existir, ajuste import se necessário
      _tempoMedioEstimado = await TempoExecucaoRepository().buscarTempoMedio(chave);
      await TempoExecucaoRepository().salvarTempo(chave, tempoMs);
    } catch (_) {
      // ignora erro se não implementado
      _tempoMedioEstimado = null;
    }

    _cronometroTimer?.cancel();
    if (resultados.length == 1) {
      // Atualiza _qtdManual ANTES do setState para garantir sincronização do Slider
      _qtdManual = resultados.first.colaboradores;
    }
    if (!mounted) return;
    final bool resultadoEhUnico = resultados.length == 1;
    final resumoUnico = resultadoEhUnico ? resultados.first : null;
    if (mounted) {
      setState(() {
        _resumos = resultados;
        _faturamento = resumoUnico?.fat;
        _colaborador = resultadoEhUnico
            ? EmpresaColaborador(idempresa: resumoUnico!.empresa.id, ano: _ano, mes: _mes, numcolaboradores: resumoUnico.colaboradores)
            : null;
        _qtdManual = resultadoEhUnico ? resumoUnico!.colaboradores : _qtdManual;
        _loading = false;

        EmpresaColaboradorPageCache.instance.salvar(
          resumos: resultados.map((r) => EmpresaResumoCacheEntry(
            empresa: r.empresa,
            colaboradores: r.colaboradores,
            fat: r.fat,
          )).toList(),
          faturamento: _faturamento,
          colaborador: _colaborador,
          qtdManual: _qtdManual,
          empresaSelecionada: _empresaSelecionada,
          ano: _ano,
          mes: _mes,
          tempoMedioEstimado: _tempoMedioEstimado,
        );
        // Adiciona atualização dos últimos filtros após salvar no cache
        _lastEmpresaSelecionada = _empresaSelecionada;
        _lastAno = _ano;
        _lastMes = _mes;
        // Restaura visualmente os filtros após consulta
        _empresaSelecionada = _lastEmpresaSelecionada;
        _ano = _lastAno ?? _ano;
        _mes = _lastMes ?? _mes;
        // Garante que os filtros fiquem ativos após término da consulta
        _empresaSelecionada = _lastEmpresaSelecionada;
        _ano = _lastAno ?? _ano;
        _mes = _lastMes ?? _mes;
      });

      // ✅ Força rebuild correto mesmo após carregamento múltiplo
      if ((_empresaSelecionada?.id ?? 0) == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }

      _lastResumos = resultados.map((r) => EmpresaResumoCacheEntry(
        empresa: r.empresa,
        colaboradores: r.colaboradores,
        fat: r.fat,
      )).toList();
      _lastFaturamento = _faturamento;
      _lastColaborador = _colaborador;
      _lastQtdManual = _qtdManual;
    }
    // Ao final, limpa controle global
    _globalFuture = null;
    _globalConsultaInicio = null;
    _lastQtdManual = _qtdManual;
    // Força reconstrução da tela no próximo frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final qtdColab = _qtdManual;
    final fat = _faturamento;
    // Restaura estimativa salva caso o valor atual seja nulo
    _tempoMedioEstimado ??= _lastTempoMedioEstimado;

    final valorPorColab = (qtdColab != null && qtdColab > 0 && fat != null)
        ? fat.totalVenda / qtdColab
        : null;

    // Garanta que os botões de filtro usem os valores restaurados
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PopupMenuButton<Empresa>(
                  tooltip: 'Selecionar empresa',
                  enabled: true, // ✅ Sempre permite selecionar empresa, independentemente do estado
                  itemBuilder: (ctx) => _empresas
                      .map((e) => PopupMenuItem(
                            value: e,
                            child: Text(e.toString()),
                          ))
                      .toList(),
                  onSelected: (e) {
                    setState(() {
                      _globalFuture = null;
                      _resumos = [];
                      _faturamento = null;
                      _colaborador = null;
                      _qtdManual = null;
                      _empresaSelecionada = e;
                      _globalFuture = null; // Libera nova consulta

                      // 🔁 Atualiza estimativa do cronômetro ao mudar o filtro
                      if (_empresaSelecionada != null) {
                        final dias = DateTime(_ano, _mes + 1, 0).difference(DateTime(_ano, _mes, 1)).inDays;
                        final chave = '${_empresaSelecionada?.id == 0 ? _empresas.where((e) => e.id != 0).map((e) => e.id).join(",") : _empresaSelecionada!.id}|$dias';
                        TempoExecucaoRepository().buscarTempoMedio(chave).then((media) {
                          if (media != null && mounted) {
                            setState(() => _tempoMedioEstimado = media);
                          }
                        });
                        // 🆕 Salva o tempo estimado para o filtro
                        if (_tempoExecucao != null) {
                          TempoExecucaoRepository().salvarTempo(chave, (_tempoExecucao! * 1000).round());
                        }
                      }
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                    _empresas = List.from(_empresas); // Força rebuild do widget
                    _iniciarConsulta();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business, size: 18, color: Colors.black87),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _empresaSelecionada?.toString() ?? 'Empresa',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black87),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
                const SizedBox(height: 8),
                PopupMenuButton<Map<String, int>>(
                  tooltip: 'Selecionar mês/ano',
                  enabled: !_loading,
                  itemBuilder: (ctx) {
                    final hoje = DateTime.now();
                    return List.generate(12, (i) {
                      final date = DateTime(hoje.year, hoje.month - i);
                      return PopupMenuItem<Map<String, int>>(
                        value: {'mes': date.month, 'ano': date.year},
                        child: Text(toBeginningOfSentenceCase(DateFormat('MMMM / yyyy', 'pt_BR').format(date)) ?? ''),
                      );
                    });
                  },
                  onSelected: (map) {
                    if (!_loading) {
                      setState(() {
                        _mes = map['mes']!;
                        _ano = map['ano']!;
                        _globalFuture = null;

                        // 🔁 Atualiza estimativa do cronômetro ao mudar o filtro
                        if (_empresaSelecionada != null) {
                          final dias = DateTime(_ano, _mes + 1, 0).difference(DateTime(_ano, _mes, 1)).inDays;
                          final chave = '${_empresaSelecionada?.id == 0 ? _empresas.where((e) => e.id != 0).map((e) => e.id).join(",") : _empresaSelecionada!.id}|$dias';
                          TempoExecucaoRepository().buscarTempoMedio(chave).then((media) {
                            if (media != null && mounted) {
                              setState(() => _tempoMedioEstimado = media);
                            }
                          });
                          // 🆕 Salva o tempo estimado para o filtro
                          if (_tempoExecucao != null) {
                            TempoExecucaoRepository().salvarTempo(chave, (_tempoExecucao! * 1000).round());
                          }
                        }
                      });
                      _iniciarConsulta();
                    }
                  },
                  child: TextButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 18, color: Colors.black87),
                    label: Text(
                      toBeginningOfSentenceCase(DateFormat('MMMM / yyyy', 'pt_BR').format(DateTime(_ano, _mes))) ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black87),
                    ),
                    onPressed: null,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                if (_empresaSelecionada != null && _empresaSelecionada!.id != 0 && _faturamento != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Colaboradores:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Botão de diminuir
                            GestureDetector(
                              onTap: (_qtdManual ?? 0) > 0
                                  ? () => setState(() => _qtdManual = (_qtdManual ?? 1) - 1)
                                  : null,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.remove, size: 18),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Botão de aumentar
                            GestureDetector(
                              onTap: () => setState(() => _qtdManual = (_qtdManual ?? 0) + 1),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add, size: 18),
                              ),
                            ),
                            const SizedBox(width: 2),
                            // Slider
                            Flexible(
                              flex: 10,
                              child: Slider(
                                value: (_qtdManual ?? 0).toDouble(),
                                min: 0,
                                max: 150,
                                divisions: 150,
                                label: '${_qtdManual ?? 0}',
                                onChanged: (value) {
                                  setState(() {
                                    _qtdManual = value.round();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${_qtdManual ?? 0}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Cabeçalho "Faturamento do Período" exibido condicionalmente conforme filtros selecionados
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Faturamento do Período', // TODO: Localizar este texto via l10n se necessário
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: '  ${_cronometro.toStringAsFixed(1)}s',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          // Exibe _tempoMedioEstimado SOMENTE se empresa e período selecionados
                          if (_empresaSelecionada != null && _ano != null && _mes != null && _tempoMedioEstimado != null)
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
            const SizedBox(height: 8),
            // Exibe progresso de carregamento das empresas no modo "Todas as Empresas"
            if (_empresaSelecionada?.id == 0 && _loading && _empresasCarregadas.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Carregando empresas...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _empresasCarregadas.entries.map((entry) {
                      final nome = _empresas.firstWhere((e) => e.id == entry.key).nome;
                      return Chip(
                        label: Text(nome),
                        avatar: Icon(
                          entry.value ? Icons.check_circle : Icons.hourglass_top,
                          color: entry.value ? Colors.green : Colors.orange,
                          size: 16,
                        ),
                        backgroundColor: entry.value ? Colors.green.shade50 : Colors.orange.shade50,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if ((_empresaSelecionada?.id ?? 0) == 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Chip Por Colaborador
                      FilterChip(
                        label: const Text('Por Colaborador'),
                        selected: _porColaborador,
                        onSelected: (v) {
                          if (v) {
                            setState(() => _porColaborador = true);
                          }
                        },
                        backgroundColor: Colors.grey.shade200,
                        selectedColor: Colors.grey.shade200,
                        checkmarkColor: Colors.black87,
                        labelStyle: const TextStyle(color: Colors.black87),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: _porColaborador ? Colors.black87 : Colors.transparent,
                            width: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Chip Totais
                      FilterChip(
                        label: const Text('Totais'),
                        selected: !_porColaborador,
                        onSelected: (v) {
                          if (v) {
                            setState(() => _porColaborador = false);
                          }
                        },
                        backgroundColor: Colors.grey.shade200,
                        selectedColor: Colors.grey.shade200,
                        checkmarkColor: Colors.black87,
                        labelStyle: const TextStyle(color: Colors.black87),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: !_porColaborador ? Colors.black87 : Colors.transparent,
                            width: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  EmpresaComparativoTable(
                    resumos: _resumos,
                    porColaborador: _porColaborador,
                    onQtdColabChanged: _atualizarColab,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Legenda com base nacional:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _LegendChip(label: 'Ruim ≤ 25 mil', color: Colors.red),
                            _LegendChip(label: 'Bom > 25 mil e ≤ 30 mil', color: Colors.orange),
                            _LegendChip(label: 'Ótimo > 30 mil e ≤ 35 mil', color: Colors.green),
                            _LegendChip(label: 'Excelente > 35 mil', color: Colors.blue),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else if ((_empresaSelecionada?.id ?? 0) == 0 && _resumos.isEmpty)
                const Text('Nenhum dado encontrado.')
              else
                Column(
                  children: [
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
                        _DashboardCard(
                          title: 'Líquido',
                          value: currency.format(fat?.totalVenda ?? 0),
                          icon: Icons.paid,
                        ),
                        _DashboardCard(
                          title: 'Bruto',
                          value: currency.format(fat?.totalVendaBruta ?? 0),
                          icon: Icons.attach_money,
                        ),
                      ],
                    ),
                    // Indicadores por Colaborador
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Indicadores por Colaborador',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                        _DashboardCard(
                          title: 'Venda Líquida',
                          value: currency.format((qtdColab ?? 0) > 0 ? (fat?.totalVenda ?? 0) / qtdColab! : 0),
                          icon: Icons.trending_up,
                          color: _corPorValor((qtdColab ?? 0) > 0 ? (fat?.totalVenda ?? 0) / qtdColab! : 0),
                        ),
                        _DashboardCard(
                          title: 'Venda Bruta',
                          value: currency.format((qtdColab ?? 0) > 0 ? (fat?.totalVendaBruta ?? 0) / qtdColab! : 0),
                          icon: Icons.stacked_line_chart,
                          color: _corPorValor((qtdColab ?? 0) > 0 ? (fat?.totalVendaBruta ?? 0) / qtdColab! : 0),
                        ),
                        _DashboardCard(
                          title: 'Lucro Líquido',
                          value: currency.format((qtdColab ?? 0) > 0 ? (fat?.lucro ?? 0) / qtdColab! : 0),
                          icon: Icons.show_chart,
                        ),
                        _DashboardCard(
                          title: 'Lucro Bruto',
                          value: currency.format((qtdColab ?? 0) > 0 ? (fat?.lucroBruto ?? 0) / qtdColab! : 0),
                          icon: Icons.bar_chart,
                        ),
                        _DashboardCard(
                          title: 'Devoluções',
                          value: currency.format((qtdColab ?? 0) > 0 ? (fat?.devolucoes ?? 0) / qtdColab! : 0),
                          icon: Icons.replay_circle_filled,
                        ),
                        _DashboardCard(
                          title: 'Nº Vendas',
                          value: (qtdColab ?? 0) > 0 ? ((fat?.nroVendas ?? 0) / qtdColab!).toStringAsFixed(1) : '0,0',
                          icon: Icons.shopping_cart_checkout,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Legenda com base nacional:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _LegendChip(label: 'Ruim ≤ 25 mil', color: Colors.red),
                              _LegendChip(label: 'Bom > 25 mil e ≤ 30 mil', color: Colors.orange),
                              _LegendChip(label: 'Ótimo > 30 mil e ≤ 35 mil', color: Colors.green),
                              _LegendChip(label: 'Excelente > 35 mil', color: Colors.blue),
                            ],
                          ),
                        ],
                      ),
                    ),
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
  final Color? color;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    this.color,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color ?? const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? Colors.black),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color ?? Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.1),
      shape: StadiumBorder(side: BorderSide(color: color)),
      labelStyle: TextStyle(color: color),
    );
  }
}

class _EmpresaResumo {
  final Empresa empresa;
  final int colaboradores;
  final FaturamentoComLucro? fat;

  _EmpresaResumo({
    required this.empresa,
    required this.colaboradores,
    required this.fat,
  });
}
// --- Cabeçalho da DataTable ---
// --- Botão que repete ação enquanto o usuário mantém pressionado ---
class _HoldButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _HoldButton({required this.icon, required this.onTap});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _timer;

  void _startTimer() {
    widget.onTap?.call(); // dispara imediatamente
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      widget.onTap?.call();
    });
  }

  void _stopTimer() => _timer?.cancel();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Caso onTap seja nulo (desabilitado), renderiza ícone opaco
    final color = widget.onTap == null
        ? Colors.grey.shade400
        : Theme.of(context).iconTheme.color;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (_) => _startTimer(),
      onLongPressEnd: (_) => _stopTimer(),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(widget.icon, size: 16, color: color),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Head(this.text, this.icon);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: const Color(0xFF2E7D32)),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

// --- Tabela comparativa por empresa ---
class EmpresaComparativoTable extends StatelessWidget {
  final List<_EmpresaResumo> resumos;
  final bool porColaborador;
  final Function(Empresa, int) onQtdColabChanged;

  const EmpresaComparativoTable({
    super.key,
    required this.resumos,
    required this.porColaborador,
    required this.onQtdColabChanged,
  });

  Color _corPorValor(double valor) {
    if (valor <= 25000) return Colors.red;
    if (valor <= 30000) return Colors.orange;
    if (valor <= 35000) return Colors.green;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        // headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
        columns: const [
          DataColumn(label: _Head('Empresa', Icons.business)),
          DataColumn(label: _Head('Colab.', Icons.people)),
          DataColumn(label: _Head('Venda Bruta', Icons.attach_money)),
          DataColumn(label: _Head('Venda Líq.', Icons.paid)),
          DataColumn(label: _Head('Lucro Bruto', Icons.bar_chart)),
          DataColumn(label: _Head('Lucro Líq.', Icons.show_chart)),
          DataColumn(label: _Head('Devoluções', Icons.replay_circle_filled)),
          DataColumn(label: _Head('Nº Vendas', Icons.shopping_cart_checkout)),
        ],
        rows: resumos.map((r) {
          final fat = r.fat;
          final colab = r.colaboradores;
          final divisor = (porColaborador && colab > 0) ? colab : 1;

          return DataRow(cells: [
            DataCell(Text(r.empresa.nome)),
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botão de subtrair (-)
                  _HoldableColabButton(
                    icon: Icons.remove,
                    enabled: colab > 0,
                    color: colab > 0 ? Colors.red.shade50 : Colors.grey.shade100,
                    onTap: colab > 0 ? () => onQtdColabChanged(r.empresa, colab - 1) : null,
                    onHold: colab > 0 ? () => onQtdColabChanged(r.empresa, colab - 1) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('$colab', style: const TextStyle(fontSize: 16)),
                  ),
                  // Botão de adicionar (+)
                  _HoldableColabButton(
                    icon: Icons.add,
                    enabled: true,
                    color: Colors.green.shade50,
                    onTap: () => onQtdColabChanged(r.empresa, colab + 1),
                    onHold: () => onQtdColabChanged(r.empresa, colab + 1),
                  ),
                ],
              ),
            ),
            DataCell(Text(
              currency.format((fat?.totalVendaBruta ?? 0) / divisor),
              style: TextStyle(color: _corPorValor((fat?.totalVendaBruta ?? 0) / divisor)),
            )),
            DataCell(Text(
              currency.format((fat?.totalVenda ?? 0) / divisor),
              style: TextStyle(color: _corPorValor((fat?.totalVenda ?? 0) / divisor)),
            )),
            DataCell(Text(currency.format((fat?.lucroBruto ?? 0) / divisor))),
            DataCell(Text(currency.format((fat?.lucro ?? 0) / divisor))),
            DataCell(Text(currency.format((fat?.devolucoes ?? 0) / divisor))),
            DataCell(Text(((fat?.nroVendas ?? 0) / divisor).toStringAsFixed(1))),
          ]);
        }).toList(),
      ),
    );
  }

  Future<int?> _editarColab(BuildContext context, int atual) async {
    final ctrl = TextEditingController(text: '$atual');
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Colaboradores'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantidade'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
// Botão customizado para segurar e repetir ação (com controle de Timer e PointerRouter)
class _HoldableColabButton extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onHold;
  const _HoldableColabButton({
    required this.icon,
    required this.enabled,
    required this.color,
    this.onTap,
    this.onHold,
    Key? key,
  }) : super(key: key);

  @override
  State<_HoldableColabButton> createState() => _HoldableColabButtonState();
}

class _HoldableColabButtonState extends State<_HoldableColabButton> {
  Timer? _timer;
  // Para garantir que removemos o route correto
  PointerRoute? _route;

  void _startHold(PointerDownEvent _) {
    if (!widget.enabled || widget.onHold == null) return;
    widget.onHold!(); // dispara imediatamente
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (widget.enabled) widget.onHold!();
    });
    // Adiciona route para detectar PointerUp/Cancel
    _route = (event) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _timer?.cancel();
        if (_route != null) {
          GestureBinding.instance.pointerRouter.removeGlobalRoute(_route!);
          _route = null;
        }
      }
    };
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route!);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_route != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_route!);
      _route = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onLongPressStart: (details) {
        // Inicia o timer e pointer route
        _startHold(details.globalPosition is PointerDownEvent
            ? details.globalPosition as PointerDownEvent
            : PointerDownEvent());
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, size: 18, color: Colors.black87),
      ),
    );
  }
}
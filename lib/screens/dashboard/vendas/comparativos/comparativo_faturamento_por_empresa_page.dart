import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/repositories/vendas/faturamento_com_lucro_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class ComparativoFaturamentoEmpresas extends StatefulWidget {
  const ComparativoFaturamentoEmpresas({super.key});

  @override
  State<ComparativoFaturamentoEmpresas> createState() => _ComparativoFaturamentoEmpresasVendasDiarioState();
}

class _ComparativoFaturamentoEmpresasVendasDiarioState extends State<ComparativoFaturamentoEmpresas> {
  // Variáveis de filtro de datas
  DateTimeRange? dateRange;
  DateTimeRange? dateRangeComparativo;
  String _filtroSelecionado = 'Hoje';
  String _filtroComparativo = 'Ontem';
  final List<String> _filtrosDisponiveis = [
    'Ontem',
    'Hoje',
    'Semana passada',
    'Esta semana',
    'Mês passado',
    'Este mês',
    'Ano passado',
    'Este ano'
  ];
  final List<String> _filtrosComparativosDisponiveis = [
    'Ontem',
    'Semana anterior',
    'Mês anterior',
    'Ano anterior'
  ];
  // Altura total do gráfico (inclui eixo X) e espaço reservado para os títulos do eixo X.
  static const double _chartHeight = 400;
  static const double _bottomReservedSize = 60;
  final ScrollController _scrollControllerHorizontal = ScrollController(initialScrollOffset: 0);

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];

  bool _loading = true;
  String _loadingMessage = '';
  // Map para armazenar dados comparativos: empresa -> {'periodo1': valor, 'periodo2': valor}
  Map<String, Map<String, double>> dadosPorEmpresa = {}; // empresa -> {'periodo1': valor, 'periodo2': valor}
  double maxValor = 1.0;
  double _computedMaxY = 1.0;
  double _intervalY = 10000;

  Map<String, bool> _loadStatus = {};

  double _roundUpToNice(double value) {
    const double step = 100000;
    return (value <= 0) ? step : (((value + step) / step).ceil() * step).toDouble();
  }

  // Intervalo "bonito" (nice) para o eixo Y de acordo com o valor máximo.
  double _calculateInterval(double maxValue) {
    if (maxValue <= 200000) return 50000;      // até 200 k → 50 k
    if (maxValue <= 1000000) return 100000;    // até 1 M  → 100 k
    if (maxValue <= 5000000) return 250000;    // até 5 M  → 250 k
    if (maxValue <= 10000000) return 500000;   // até 10 M → 500 k
    return 1000000;                            // acima de 10 M → 1 M
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollControllerHorizontal.jumpTo(0);
    });
    // Inicializa filtros e datas padrão
    dateRange = _calcularIntervaloPorFiltro(_filtroSelecionado, comparativo: false);
    dateRangeComparativo = _calcularIntervaloPorFiltro(_filtroComparativo, comparativo: true, ref: dateRange);
    Future.microtask(() => _carregarDados());
  }

  Future<void> _carregarDados() async {
    final authService = AuthService();
    final apiClient = ApiClient(authService);
    final cadLojasService = CadLojasService(apiClient);
    final fatRepository = FaturamentoComLucroRepository(apiClient);

    final empresas = await cadLojasService.getEmpresasDisponiveis();
    final empresasComNome = await cadLojasService.getEmpresasComNome();

    _empresas = empresasComNome;

    final idsFiltrados = _empresasSelecionadas.isNotEmpty
        ? _empresasSelecionadas.map((e) => e.id).toList()
        : empresas;
    // Inicializa o status de carregamento para cada empresa
    final nomesParaCarregar = empresasComNome
        .where((e) => idsFiltrados.contains(e.id))
        .map((e) => e.nome)
        .toList();
    if (!mounted) return;
    setState(() {
      _loadStatus = {for (var nome in nomesParaCarregar) nome: false};
    });
    dadosPorEmpresa.clear();
    for (final id in idsFiltrados) {
      final empresa = empresasComNome.firstWhere((e) => e.id == id, orElse: () => Empresa(id: id, nome: 'Empresa $id'));
      final nomeEmpresa = empresa.nome;
      if (!mounted) return;
      setState(() {
        _loadingMessage = 'Aguarde, carregando dados da empresa $nomeEmpresa';
      });

      // Coleta do período principal
      double totalPeriodoPrincipal = 0.0;
      // Prints antes da chamada principal
      print('🔎 Principal Empresa: $id');
      print('🗓️ Data Início Principal: ${dateRange!.start.toIso8601String()}');
      print('🗓️ Data Fim Principal: ${dateRange!.end.toIso8601String()}');
      print('🕒 Timezone Local: ${DateTime.now().timeZoneName}');
      try {
        final listaPrincipal = await fatRepository.getResumoFaturamentoComLucro(
          idEmpresa: id,
          dataInicial: dateRange!.start,
          dataFinal:   dateRange!.end,
        );
        totalPeriodoPrincipal = listaPrincipal.fold<double>(
          0.0, (sum, item) => sum + item.totalVenda
        );
      } catch (_) {
        totalPeriodoPrincipal = 0.0;
      }

      // Coleta do período comparativo
      double totalPeriodoComparativo = 0.0;
      if (dateRangeComparativo != null) {
        // Prints antes da chamada comparativa
        print('🔎 Comparativo Empresa: $id');
        print('🗓️ Data Início Comparativo: ${dateRangeComparativo!.start.toIso8601String()}');
        print('🗓️ Data Fim Comparativo: ${dateRangeComparativo!.end.toIso8601String()}');
        print('🕒 Timezone Local: ${DateTime.now().timeZoneName}');
        try {
          final listaComparativo = await fatRepository.getResumoFaturamentoComLucro(
            idEmpresa: id,
            dataInicial: dateRangeComparativo!.start,
            dataFinal:   dateRangeComparativo!.end,
          );
          totalPeriodoComparativo = listaComparativo.fold<double>(
            0.0, (sum, item) => sum + item.totalVenda
          );
        } catch (_) {
          totalPeriodoComparativo = 0.0;
        }
      }

      // Não inclui empresas com ambos os valores zero
      if (totalPeriodoPrincipal == 0.0 && totalPeriodoComparativo == 0.0) {
        continue;
      }
      dadosPorEmpresa['$nomeEmpresa'] = {
        'periodo1': totalPeriodoPrincipal,
        'periodo2': totalPeriodoComparativo,
      };
      // Marca empresa como concluída
      if (!mounted) return;
      setState(() {
        _loadStatus[nomeEmpresa] = true;
      });
    }

    if (!mounted) return;
    setState(() {
      _loadingMessage = 'Carregamento concluído.';
    });

    double maxLocal = dadosPorEmpresa.values
        .expand((m) => m.values)
        .fold(0.0, (prev, el) => el > prev ? el : prev);
    final computedMaxY = _roundUpToNice(maxLocal + 100000);

    if (!mounted) return;
    setState(() {
      _loading = false;
      maxValor = computedMaxY;
      _computedMaxY = computedMaxY;
      _intervalY = _calculateInterval(_computedMaxY);
    });
  }

  // Novo filtro de datas via bottom sheet customizado
  Future<void> _abrirFiltroDatas() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
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
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          child: Builder(
            builder: (context) {
              return StatefulBuilder(
                builder: (BuildContext context, StateSetter setStateModal) {
                  return Padding(
                    padding: MediaQuery.of(context).viewInsets,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(title: const Text('Filtro Manual')),
                        ListTile(
                          title: const Text('Data Inicial'),
                          trailing: Text(DateFormat('dd/MM/yyyy').format(dateRange?.start ?? DateTime.now())),
                          onTap: () async {
                            final selectedDate = await showDatePicker(
                              context: context,
                              initialDate: dateRange?.start ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (selectedDate != null) {
                              setStateModal(() {
                                dateRange = DateTimeRange(
                                  start: selectedDate,
                                  end: dateRange?.end ?? selectedDate
                                );
                              });
                            }
                          },
                        ),
                        ListTile(
                          title: const Text('Data Final'),
                          trailing: Text(DateFormat('dd/MM/yyyy').format(dateRange?.end ?? DateTime.now())),
                          onTap: () async {
                            final selectedDate = await showDatePicker(
                              context: context,
                              initialDate: dateRange?.end ?? DateTime.now(),
                              firstDate: dateRange?.start ?? DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (selectedDate != null) {
                              setStateModal(() {
                                dateRange = DateTimeRange(
                                  start: dateRange?.start ?? selectedDate,
                                  end: selectedDate
                                );
                              });
                            }
                          },
                        ),
                        const Divider(),
                        ListTile(title: const Text('Filtros Normais')),
                        Wrap(
                          spacing: 6.0,
                          children: _filtrosDisponiveis.map((filtro) {
                            return ChoiceChip(
                              label: Text(filtro),
                              selected: _filtroSelecionado == filtro,
                              selectedColor: const Color(0xFF2E7D32),
                              backgroundColor: Colors.white,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _filtroSelecionado == filtro ? Colors.white : Colors.black,
                              ),
                              onSelected: (_) {
                                setStateModal(() {
                                  _filtroSelecionado = filtro;
                                  dateRange = _calcularIntervaloPorFiltro(filtro);
                                  dateRangeComparativo = _calcularComparativoAutomatico(dateRange!, _filtroComparativo);
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const Divider(),
                        ListTile(title: const Text('Compare com:')),
                        Wrap(
                          spacing: 6.0,
                          children: _filtrosComparativosDisponiveis.map((filtro) {
                            bool isDisabled = !_validarComparativo(_filtroSelecionado, filtro, dateRange, dateRangeComparativo);
                            return ChoiceChip(
                              label: Text(filtro),
                              selected: _filtroComparativo == filtro,
                              selectedColor: const Color(0xFF2E7D32),
                              backgroundColor: Colors.white,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _filtroComparativo == filtro ? Colors.white : Colors.black,
                              ),
                              onSelected: isDisabled
                                  ? null
                                  : (_) {
                                      setStateModal(() {
                                        _filtroComparativo = filtro;
                                        dateRangeComparativo = _calcularComparativoAutomatico(dateRange!, filtro);
                                      });
                                    },
                              disabledColor: Colors.grey.shade300,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          child: const Text('Aplicar'),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _loading = true;
                              dadosPorEmpresa.clear();
                            });
                            _carregarDados();
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // Calcula o intervalo de datas conforme o filtro escolhido
  DateTimeRange? _calcularIntervaloPorFiltro(String filtro, {bool comparativo = false, DateTimeRange? ref}) {
    final now = DateTime.now();
    switch (filtro.toUpperCase()) {
      case 'HOJE':
        return DateTimeRange(start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'ONTEM':
        final ontem = now.subtract(const Duration(days: 1));
        return DateTimeRange(
            start: DateTime(ontem.year, ontem.month, ontem.day),
            end: DateTime(ontem.year, ontem.month, ontem.day, 23, 59, 59));
      case 'ESTA SEMANA':
        final inicio = now.subtract(Duration(days: now.weekday - 1));
        final fim = inicio.add(const Duration(days: 6));
        return DateTimeRange(start: inicio,
            end: DateTime(fim.year, fim.month, fim.day, 23, 59, 59));
      case 'SEMANA PASSADA':
        final fim = now.subtract(Duration(days: now.weekday));
        final inicio = fim.subtract(const Duration(days: 6));
        return DateTimeRange(start: inicio,
            end: DateTime(fim.year, fim.month, fim.day, 23, 59, 59));
      case 'ESTE MÊS':
        final inicio = DateTime(now.year, now.month, 1);
        final fim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return DateTimeRange(start: inicio, end: fim);
      case 'MÊS PASSADO':
        final mesPassado = DateTime(now.year, now.month - 1, 1);
        final fim = DateTime(now.year, now.month, 0, 23, 59, 59);
        return DateTimeRange(start: mesPassado, end: fim);
      case 'ESTE ANO':
        return DateTimeRange(start: DateTime(now.year, 1, 1),
            end: DateTime(now.year, 12, 31, 23, 59, 59));
      case 'ANO PASSADO':
        final ano = now.year - 1;
        return DateTimeRange(
            start: DateTime(ano, 1, 1), end: DateTime(ano, 12, 31, 23, 59, 59));
      case 'SEL.DATA':
        return comparativo ? dateRangeComparativo : dateRange;
      default:
        return DateTimeRange(start: now, end: now);
    }
  }

  // Calcula o intervalo comparativo automaticamente baseado no intervalo principal
  DateTimeRange _calcularComparativoAutomatico(DateTimeRange periodoPrincipal, String filtroComparativo) {
    switch (filtroComparativo.toUpperCase()) {
      case 'ONTEM':
        return DateTimeRange(
          start: periodoPrincipal.start.subtract(const Duration(days: 1)),
          end: periodoPrincipal.end.subtract(const Duration(days: 1)),
        );
      case 'SEMANA ANTERIOR':
        return DateTimeRange(
          start: periodoPrincipal.start.subtract(const Duration(days: 7)),
          end: periodoPrincipal.end.subtract(const Duration(days: 7)),
        );
      case 'MÊS ANTERIOR':
        return DateTimeRange(
          start: DateTime(periodoPrincipal.start.year, periodoPrincipal.start.month - 1, periodoPrincipal.start.day),
          end: DateTime(periodoPrincipal.end.year, periodoPrincipal.end.month - 1, periodoPrincipal.end.day, 23, 59, 59),
        );
      case 'ANO ANTERIOR':
        return DateTimeRange(
          start: DateTime(periodoPrincipal.start.year - 1, periodoPrincipal.start.month, periodoPrincipal.start.day),
          end: DateTime(periodoPrincipal.end.year - 1, periodoPrincipal.end.month, periodoPrincipal.end.day, 23, 59, 59),
        );
      default:
        return DateTimeRange(
          start: periodoPrincipal.start.subtract(const Duration(days: 1)),
          end: periodoPrincipal.end.subtract(const Duration(days: 1)),
        );
    }
  }

  // Valida se ambos os períodos estão preenchidos corretamente
  bool _validarComparativo(String filtroPrincipal, String filtroComparativo, DateTimeRange? intervaloPrincipal, DateTimeRange? intervaloComparativo) {
    if (filtroPrincipal == 'Sel.Data' && intervaloPrincipal == null) return false;
    if (filtroComparativo == 'Sel.Data' && intervaloComparativo == null) return false;
    return true;
  }

  String formatEixoCurrency(double value) {
    if (value >= 1000000) {
      return '${(value ~/ 1000000)} M';
    } else if (value >= 1000) {
      return '${(value ~/ 1000)} K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  String formatCurrencyReal(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  /// Eixo Y fixo (régua) – corresponde aos mesmos valores que o gráfico
  Widget _buildFixedYAxis({required double height}) {
    // Gera os valores de topo para baixo (ex.: 1 000 000, 950 000, …, 0)
    final double step = _intervalY;
    final int steps = (_computedMaxY ~/ step);
    final values = List<double>.generate(steps + 1, (i) => _computedMaxY - i * step);

    return SizedBox(
      width: 30, // aumentada para manter alinhamento visual consistente
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: values
            .map((v) => Text(
          formatEixoCurrency(v),
          style: const TextStyle(fontSize: 10),
        ))
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Para o gráfico comparativo: cada empresa terá duas barras (periodo1 e periodo2)
    final empresasOrdenadas = dadosPorEmpresa.keys.toList();
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Colors.black87),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Carregando dados...', style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _loadStatus.entries.map((entry) {
                      return Padding(
                        // === ALTERAÇÃO: adicionar recuo horizontal e centralizar conteúdo do loading ===
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
                        child: Row(
                          // === ALTERAÇÃO: permitir quebra responsiva e evitar overflow horizontal de nomes longos ===
                          mainAxisSize: MainAxisSize.max,
                          // === ALTERAÇÃO: centralizar conteúdo do loading ===
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // === ALTERAÇÃO: Text envolto em Flexible com ellipsis ===
                            Flexible(
                              // === ALTERAÇÃO: remover 'Supermercado(s)' (qualquer parte, case-insensitive) no loading ===
                              child: Text(
                                entry.key
                                    .replaceAll(RegExp(r'supermercados?\s*', caseSensitive: false), '')
                                    .trim()
                                    .replaceAll(RegExp(r'\s{2,}'), ' '),
                                style: const TextStyle(fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 8),
                            entry.value
                                ? const Icon(Icons.check, color: Colors.green)
                                : const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.filter_alt, size: 18, color: Colors.black87),
                            label: const Text(
                              'Datas',
                              style: TextStyle(color: Colors.black87),
                            ),
                            onPressed: _abrirFiltroDatas,
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              backgroundColor: Colors.grey.shade200,
                              elevation: 0, // Remover sombra
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildFiltroEmpresas(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Faturamento Diário por Empresa',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _chartHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 0),
                        Padding(
                          padding: EdgeInsets.only(left: 0, bottom: _bottomReservedSize),
                          child: _buildFixedYAxis(height: _chartHeight - _bottomReservedSize),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: _scrollControllerHorizontal,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: SizedBox(
                                width: max(MediaQuery.of(context).size.width, empresasOrdenadas.length * 100.0 + 60),
                                child: BarChart(
                                  BarChartData(
                                    barTouchData: BarTouchData(
                                      enabled: true,
                                      touchTooltipData: BarTouchTooltipData(
                                        // === ALTERAÇÃO: fundo branco tooltip usando API v1.0.0 (getTooltipColor) ===
                                        getTooltipColor: (group) => Colors.white,
                                        tooltipMargin: 12,
                                        fitInsideVertically: true,
                                        fitInsideHorizontally: true,
                                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                          // === ALTERAÇÃO: sanitizar nome removendo 'Supermercado(s)' no tooltip ===
                                          final empresaOriginal = empresasOrdenadas[group.x.toInt()];
                                          final empresaLabel = empresaOriginal
                                              .replaceAll(RegExp(r'supermercados?\s*', caseSensitive: false), '')
                                              .trim()
                                              .replaceAll(RegExp(r'\s{2,}'), ' ');
                                          final dados = dadosPorEmpresa[empresaOriginal];
                                          String label = '';
                                          double valor = 0.0;
                                          if (rodIndex == 0) {
                                            label = _filtroSelecionado;
                                            valor = dados?['periodo1'] ?? 0.0;
                                          } else {
                                            label = _filtroComparativo;
                                            valor = dados?['periodo2'] ?? 0.0;
                                          }
                                          return BarTooltipItem(
                                            '$empresaLabel\n$label: ${formatCurrencyReal(valor)}',
                                            const TextStyle(
                                              color: Color(0xFF2E7D32),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: _bottomReservedSize,
                                          getTitlesWidget: (value, meta) {
                                            final index = value.toInt();
                                            if (index < empresasOrdenadas.length) {
                                              // === ALTERAÇÃO: remoção de SideTitleWidget (incompatível na fl_chart 1.0.0) substituído por Padding/SizedBox manual ===
                                              Widget title = Padding(
                                                padding: const EdgeInsets.only(top: 6.0),
                                                child: SizedBox(
                                                  width: 100,
                                                  child: Column(
                                                    children: [
                                                      const SizedBox(height: 8),
                                                      // === ALTERAÇÃO: remover também a forma singular 'Supermercado ' ===
                                                      Text(
                                                        // === CORREÇÃO: Dart RegExp não suporta inline flag (?i); usar caseSensitive: false ===
                                                        empresasOrdenadas[index]
                                                            .replaceAll(RegExp(r'supermercados?\s*', caseSensitive: false), '')
                                                            .trim()
                                                            .replaceAll(RegExp(r'\s{2,}'), ' '),
                                                        style: const TextStyle(fontSize: 10),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                              if (index == 0) {
                                                return Padding(
                                                  padding: const EdgeInsets.only(left: 10),
                                                  child: title,
                                                );
                                              }
                                              return title;
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ),
                                      // O eixo Y dentro do gráfico fica oculto,
                                      // pois agora usamos a régua fixa
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(showTitles: false, reservedSize: 60),
                                      ),
                                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    ),
                                    gridData: FlGridData(
                                      show: true,
                                      horizontalInterval: _intervalY,
                                      getDrawingHorizontalLine: (value) => FlLine(
                                        color: Colors.grey.shade300,
                                        strokeWidth: 1,
                                        dashArray: [5, 5],
                                      ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    minY: 0,
                                    maxY: _computedMaxY,
                                    alignment: BarChartAlignment.spaceAround,
                                    barGroups: empresasOrdenadas.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final dados = dadosPorEmpresa[entry.value] ?? {};
                                      final valor1 = dados['periodo1'] ?? 0.0;
                                      final valor2 = dados['periodo2'] ?? 0.0;
                                      return BarChartGroupData(
                                        x: index,
                                        barsSpace: 8,
                                        barRods: [
                                          BarChartRodData(
                                            toY: valor1,
                                            width: 14,
                                            color: const Color(0xFF2E7D32),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          BarChartRodData(
                                            toY: valor2,
                                            width: 14,
                                            color: Colors.grey.shade500,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // REMOVE any extra vertical spacing (e.g., SizedBox) between the chart and legend
                  // (there is none here, so nothing to remove)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle, size: 12, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 8),
                              Text(
                                'Filtro Normal: ${dateRange != null ? DateFormat('dd/MM/yyyy').format(dateRange!.start) : ''} - ${dateRange != null ? DateFormat('dd/MM/yyyy').format(dateRange!.end) : ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 12, color: Colors.grey.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Comparado com: ${dateRangeComparativo != null ? DateFormat('dd/MM/yyyy').format(dateRangeComparativo!.start) : ''} - ${dateRangeComparativo != null ? DateFormat('dd/MM/yyyy').format(dateRangeComparativo!.end) : ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }


  /// Botão de seleção de empresas com estilo igual ao botão 'Datas'
  Widget _buildFiltroEmpresas() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.business, size: 18, color: Colors.black87),
      label: Text(
        _empresasSelecionadas.isEmpty
            ? 'Todas as Empresas'
            : _empresasSelecionadas.map((e) => e.nome).join(', '),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.black87),
      ),
      onPressed: _abrirFiltroEmpresas,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.black87,
        backgroundColor: Colors.grey.shade200,
        elevation: 0, // Remover sombra
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Future<void> _abrirFiltroEmpresas() async {
    await showDialog(
      context: context,
      builder: (context) {
        List<Empresa> tempSelecionadas = [..._empresasSelecionadas];
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            bool todasSelecionadas = tempSelecionadas.length == _empresas.length;

            return AlertDialog(
              title: const Text('Selecionar Empresas'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CheckboxListTile(
                      title: const Text('Todas as Empresas'),
                      value: todasSelecionadas,
                      onChanged: (bool? value) {
                        setStateDialog(() {
                          if (value == true) {
                            tempSelecionadas = List.from(_empresas);
                          } else {
                            tempSelecionadas.clear();
                          }
                        });
                      },
                    ),
                    ..._empresas.map((empresa) {
                      final selecionada = tempSelecionadas.contains(empresa);
                      return CheckboxListTile(
                        title: Text(empresa.nome),
                        value: selecionada,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            if (value == true) {
                              tempSelecionadas.add(empresa);
                            } else {
                              tempSelecionadas.remove(empresa);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _empresasSelecionadas = tempSelecionadas;
                      _loading = true;
                      dadosPorEmpresa.clear();
                    });
                    _carregarDados();
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

}
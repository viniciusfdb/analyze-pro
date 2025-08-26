import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/repositories/vendas/faturamento_com_lucro_repository.dart';
import 'package:fl_chart/fl_chart.dart';

class ComparativoFaturamentoEmpresasVendas extends StatefulWidget {
  const ComparativoFaturamentoEmpresasVendas({super.key});

  @override
  State<ComparativoFaturamentoEmpresasVendas> createState() => _ComparativoFaturamentoEmpresasVendasState();
}

class _ComparativoFaturamentoEmpresasVendasState extends State<ComparativoFaturamentoEmpresasVendas> {
  DateTimeRange? dateRange;
  bool _loading = true;
  Map<String, double> dadosFaturamento = {};
  double maxValor = 1.0;
  // ===== INÍCIO ALTERAÇÃO: constantes de tamanho do gráfico =====
  static const double _chartHeight = 400;
  static const double _bottomReservedSize = 60;
  // ===== FIM ALTERAÇÃO =====
  // ===== INÍCIO ALTERAÇÃO: variáveis e helpers para escala dinâmica =====
  double _computedMaxY = 1.0;
  double _intervalY = 10000;

  /// Arredonda o valor máximo para um “número bonito”
  double _roundUpToNice(double value) {
    const double step = 100000;
    return (value <= 0) ? step : (((value + step) / step).ceil() * step).toDouble();
  }

  /// Calcula um intervalo “agradável” para o eixo Y
  double _calculateInterval(double maxValue) {
    if (maxValue <= 200000) return 50000;      // até 200 k → 50 k
    if (maxValue <= 1000000) return 100000;    // até 1 M  → 100 k
    if (maxValue <= 5000000) return 250000;    // até 5 M  → 250 k
    if (maxValue <= 10000000) return 500000;   // até 10 M → 500 k
    return 1000000;                            // acima de 10 M → 1 M
  }

  /// Eixo Y fixo (régua) – corresponde aos mesmos valores que o gráfico
  Widget _buildFixedYAxis({required double height}) {
    final double step = _intervalY;
    final int steps = (_computedMaxY ~/ step);
    final values = List<double>.generate(steps + 1, (i) => _computedMaxY - i * step);

    return SizedBox(
      width: 30,
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
  // ===== FIM ALTERAÇÃO =====
  Map<String, bool> _loadStatus = {};
  // ===== INÍCIO ALTERAÇÃO: scroll horizontal inicia sempre no zero =====
  final ScrollController _scrollControllerHorizontal = ScrollController(initialScrollOffset: 0);
  // ===== FIM ALTERAÇÃO =====

  String formatEixoCurrency(double value) {
    if (value >= 1000000) {
      final mValue = value / 1000000;
      return '${mValue.toStringAsFixed(mValue % 1 == 0 ? 0 : 1)}\u2060M';
    } else if (value >= 1000) {
      final kValue = value / 1000;
      return '${kValue.toStringAsFixed(kValue % 1 == 0 ? 0 : 1)}\u2060K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  String formatCurrencyReal(double value) {
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return formatter.format(value);
  }

  @override
  void initState() {
    super.initState();
    // ===== INÍCIO ALTERAÇÃO: garante que o scroll esteja anexado antes de mover =====
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollControllerHorizontal.hasClients) {
        _scrollControllerHorizontal.jumpTo(0);
      }
    });
    // ===== FIM ALTERAÇÃO =====
    Future.microtask(() => _carregarDados());
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D32), // Verde mais forte para datas selecionadas
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
        dateRange = picked;
        _loading = true;
        dadosFaturamento.clear(); // limpa os dados antigos
      });
      await _carregarDados(); // recarrega com o novo período
    }
  }

  Future<void> _carregarDados() async {
    if (dateRange == null) {
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      if (args != null && args['dateRange'] is DateTimeRange) {
        dateRange = args['dateRange'];
      } else {
        final hoje = DateTime.now();
        final inicioDia = DateTime(hoje.year, hoje.month, hoje.day, 0, 0, 0);
        final fimDia = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);
        dateRange = DateTimeRange(start: inicioDia, end: fimDia);
      }
    }
    // Ajusta o intervalo para o dia inteiro caso o usuário selecione apenas um único dia
    if (dateRange!.start == dateRange!.end) {
      dateRange = DateTimeRange(
        start: DateTime(dateRange!.start.year, dateRange!.start.month, dateRange!.start.day, 0, 0, 0),
        end: DateTime(dateRange!.end.year, dateRange!.end.month, dateRange!.end.day, 23, 59, 59),
      );
    }

    dadosFaturamento.clear(); // <- adicionado aqui

    final authService = AuthService();
    final apiClient = ApiClient(authService);
    final cadLojasService = CadLojasService(apiClient);
    final fatRepository = FaturamentoComLucroRepository(apiClient);

    final empresas = await cadLojasService.getEmpresasDisponiveis();
    final empresasComNome = await cadLojasService.getEmpresasComNome();

    // Inicializa status de carregamento para cada empresa (usando nome limpo)
    setState(() {
      _loadStatus = {
        for (var e in empresasComNome)
          e.nome.replaceAll(RegExp(r'Supermercados?\s', caseSensitive: false), '').trim(): false
      };
    });

    for (final id in empresas) {
      try {
        final lista = await fatRepository.getResumoFaturamentoComLucro(
          idEmpresa: id,
          dataInicial: dateRange!.start,
          dataFinal:   dateRange!.end,
        );
        final totalLiquido = lista.fold<double>(0.0, (sum, item) => sum + item.totalVenda);
        final loja = empresasComNome.firstWhere(
              (e) => e.id == id,
          orElse: () => Empresa(id: id, nome: 'Empresa $id'),
        );
        final nomeEmpresa = loja.nome.replaceAll(RegExp(r'Supermercados?\s?', caseSensitive: false), '').trim();
        dadosFaturamento[nomeEmpresa] = totalLiquido;
        // Marca empresa como concluída
        setState(() {
          _loadStatus[nomeEmpresa] = true;
        });
      } catch (_) {}
    }

    double maxValorLocal = dadosFaturamento.values.isNotEmpty
        ? dadosFaturamento.values.reduce((a, b) => a > b ? a : b)
        : 1.0;
    maxValorLocal = max(maxValorLocal, 1.0);

    final computedMaxY = _roundUpToNice(maxValorLocal + 100000);
    setState(() {
      _loading = false;
      maxValor = computedMaxY;
      _computedMaxY = computedMaxY;
      _intervalY = _calculateInterval(_computedMaxY);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ===== INÍCIO ALTERAÇÃO: usa valores pré‑computados pela lógica nova =====
    final double interval = _intervalY;
    // ===== FIM ALTERAÇÃO =====
    final nonZeroEntries = dadosFaturamento.entries.where((e) => e.value > 0).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _loading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Carregando dados...', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: _loadStatus.entries.map((entry) {
                // ===== INÍCIO ALTERAÇÃO: ajusta largura para evitar overflow =====
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
                // ===== FIM ALTERAÇÃO =====
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
            Row(
              children: [
                TextButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    dateRange != null
                        ? '${_formatDate(dateRange!.start)} - ${_formatDate(dateRange!.end)}'
                        : 'Período',
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
                const Spacer(),
              ],
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Comparativo de Faturamento',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            nonZeroEntries.isEmpty
                ? const SizedBox(
                height: 250,
                child: Center(child: Text('Nenhum dado disponível para o período selecionado.')))
                : Column(
              children: [
                SizedBox(
                  height: _chartHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 0),
                      // ===== INÍCIO ALTERAÇÃO: eixo Y fixo =====
                      Padding(
                        padding: EdgeInsets.only(left: 0, bottom: _bottomReservedSize),
                        child: _buildFixedYAxis(height: _chartHeight - _bottomReservedSize),
                      ),
                      // ===== FIM ALTERAÇÃO =====
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _scrollControllerHorizontal,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: SizedBox(
                              width: max(MediaQuery.of(context).size.width, nonZeroEntries.length * 100.0 + 60),
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  maxY: _computedMaxY,
                                  minY: 0,
                                  // ===== INÍCIO ALTERAÇÃO: barTouchData localizado e tooltip fundo branco (fl_chart >=1.0.0) =====
                                  barTouchData: BarTouchData(
                                    enabled: true,
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipColor: (group) => Colors.white,
                                      tooltipBorderRadius: BorderRadius.circular(8),
                                      tooltipPadding: const EdgeInsets.all(8),
                                      fitInsideHorizontally: true,
                                      fitInsideVertically: true,
                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                        final empresa = nonZeroEntries[group.x.toInt()].key;
                                        final valor = rod.toY;
                                        // === ALTERAÇÃO: texto do tooltip em verde para manter padrão visual ===
                                        return BarTooltipItem(
                                          '$empresa\n${formatCurrencyReal(valor)}',
                                          const TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  // ===== FIM ALTERAÇÃO =====
                                  titlesData: FlTitlesData(
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: _bottomReservedSize,
                                        getTitlesWidget: (value, meta) {
                                          final index = value.toInt();
                                          if (index < nonZeroEntries.length) {
                                            return SideTitleWidget(
                                              space: 6.0,
                                              child: SizedBox(
                                                width: 100,
                                                child: Column(
                                                  children: [
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      nonZeroEntries[index].key.replaceAll(RegExp(r'Supermercados?\s', caseSensitive: false), ''),
                                                      style: const TextStyle(fontSize: 10),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              meta: meta,
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  gridData: FlGridData(
                                    show: true,
                                    horizontalInterval: interval,
                                    getDrawingHorizontalLine: (value) => FlLine(
                                      color: Colors.grey.shade300,
                                      strokeWidth: 1,
                                      dashArray: [5, 5],
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  barGroups: List.generate(nonZeroEntries.length, (index) {
                                    final empresa = nonZeroEntries[index].key;
                                    final valor = nonZeroEntries[index].value;
                                    return BarChartGroupData(
                                      x: index,
                                      barsSpace: 0, // Sem espaço entre as barras (só há uma por grupo)
                                      barRods: [
                                        BarChartRodData(
                                          toY: valor,
                                          width: 22, // Largura menor para barras mais finas e próximas
                                          color: const Color(0xFF2E7D32),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, size: 12, color: Color(0xFF2E7D32)),
                            const SizedBox(width: 8),
                            Text(
                              dateRange != null
                                  ? '${_formatDate(dateRange!.start)} - ${_formatDate(dateRange!.end)}'
                                  : '',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

// Função agora localizada fora da classe.
}

double calculateInterval(double max) {
  if (max <= 1000) return 100;
  // Queremos uma régua mais detalhada para faixas menores.
  if (max <= 100000) return 10000;      // Até 100 k → marcações de 5 k
  if (max <= 200000) return 10000;     // Até 200 k → marcações de 10 k
  if (max <= 1000000) return 50000;    // Até 1 M  → marcações de 50 k
  if (max <= 10000000) return 150000;  // Até 10 M → marcações de 150 k
  if (max <= 20000000) return 200000;  // Até 20 M → marcações de 200 k
  return 250000;                       // Acima disso
}
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/repositories/vendas/faturamento_com_lucro_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class ComparativoFaturamentoEmpresasDiario extends StatefulWidget {
  const ComparativoFaturamentoEmpresasDiario({super.key});

  @override
  State<ComparativoFaturamentoEmpresasDiario> createState() => _ComparativoFaturamentoEmpresasVendasDiarioState();
}

class _ComparativoFaturamentoEmpresasVendasDiarioState extends State<ComparativoFaturamentoEmpresasDiario> {
  /// Remove “Supermercado” ou “Supermercados” (qualquer posição, singular ou plural) e espaçamentos extras
  String _sanitizeNomeEmpresa(String nome) {
    // Remove “Supermercado” or “Supermercados” (qualquer posição, singular ou plural) e espaçamentos extras
    return nome
        .replaceAll(RegExp(r'Supermercados?\s?', caseSensitive: false), '')
        .trim();
  }
  // Altura total do gráfico (inclui eixo X) e espaço reservado para os títulos do eixo X.
  static const double _chartHeight = 400;
  static const double _bottomReservedSize = 60;
  final ScrollController _scrollControllerHorizontal = ScrollController(initialScrollOffset: 0);
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
  String _filtroSelecionado = 'Hoje';
  String _filtroComparativo = 'Ontem';

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];

  DateTimeRange? dateRange;
  DateTimeRange? dateRangeComparativo;
  bool _loading = true;
  Map<String, Map<String, double>> dadosPorEmpresa = {
  }; // empresa -> {data -> valor}
  double maxValor = 1.0;
  double _computedMaxY = 1.0;
  double _intervalY = 10000;   // intervalo dinâmico do eixo Y

  Map<String, bool> _loadStatus = {};

  /// Arredonda para o próximo múltiplo de 100 k (ou 100 k se 0).
  double _roundUpToNice(double value) {
    const double step = 100000;               // 100 k
    return (value <= 0)
        ? step
        : (((value + step) / step).ceil() * step).toDouble();
  }

  /// Calcula intervalo “bonito” para o eixo Y de acordo com o valor máximo
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
    dateRange = _calcularIntervaloPorFiltro(_filtroSelecionado);
    dateRangeComparativo = _calcularComparativoAutomatico(dateRange!, _filtroComparativo);
    Future.microtask(() => _carregarDados());
  }

  // Localizado e refatorado conforme solicitado
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
        .map((e) => _sanitizeNomeEmpresa(e.nome))
        .toList();
    setState(() {
      _loadStatus = {for (var nome in nomesParaCarregar) nome: false};
    });
    for (final id in idsFiltrados) {
      final empresa = empresasComNome.firstWhere((e) => e.id == id,
          orElse: () => Empresa(id: id, nome: 'Empresa $id'));
      final nomeEmpresa = _sanitizeNomeEmpresa(empresa.nome);

      Map<String, double> dadosDiarios = {};
      Map<String, double> dadosDiariosComparativo = {};
      double totalEmpresa = 0.0;
      double totalEmpresaComparativo = 0.0;

      // Período principal
      DateTime dataAtual = dateRange!.start;
      while (!dataAtual.isAfter(dateRange!.end)) {
        try {
          final dataInicio = DateTime(dataAtual.year, dataAtual.month, dataAtual.day);
          final dataFim = DateTime(dataAtual.year, dataAtual.month, dataAtual.day, 23, 59, 59);
          final lista = await fatRepository.getResumoFaturamentoComLucro(
            idEmpresa: id,
            dataInicial: dataInicio,
            dataFinal:   dataFim,
          );
          final valor = lista.fold<double>(0.0, (sum, item) => sum + item.totalVenda);
          totalEmpresa += valor;
          dadosDiarios[DateFormat('dd/MM').format(dataAtual)] = valor;
        } catch (_) {
          dadosDiarios[DateFormat('dd/MM').format(dataAtual)] = 0.0;
        }
        dataAtual = dataAtual.add(const Duration(days: 1));
      }

      // Período comparativo
      if (dateRangeComparativo != null) {
        DateTime dataAtualComparativo = dateRangeComparativo!.start;
        while (!dataAtualComparativo.isAfter(dateRangeComparativo!.end)) {
          try {
            final dataInicioComparativo = DateTime(dataAtualComparativo.year, dataAtualComparativo.month, dataAtualComparativo.day);
            final dataFimComparativo = DateTime(dataAtualComparativo.year, dataAtualComparativo.month, dataAtualComparativo.day, 23, 59, 59);
            final lista = await fatRepository.getResumoFaturamentoComLucro(
              idEmpresa: id,
              dataInicial: dataInicioComparativo,
              dataFinal:   dataFimComparativo,
            );
            final valor = lista.fold<double>(0.0, (sum, item) => sum + item.totalVenda);
            totalEmpresaComparativo += valor;
            dadosDiariosComparativo['${DateFormat('dd/MM').format(dataAtualComparativo)} (comparativo)'] = valor;
          } catch (_) {
            dadosDiariosComparativo['${DateFormat('dd/MM').format(dataAtualComparativo)} (comparativo)'] = 0.0;
          }
          dataAtualComparativo = dataAtualComparativo.add(const Duration(days: 1));
        }
      }

      // Junta ambos os mapas
      final dadosCombinados = {...dadosDiarios};

      // Adiciona os valores comparativos com uma chave diferente para não sobrescrever os principais
      dadosDiariosComparativo.forEach((key, value) {
        dadosCombinados['$key'] = value;
      });
      dadosPorEmpresa['$nomeEmpresa - ${formatCurrencyReal(totalEmpresa)} / ${formatCurrencyReal(totalEmpresaComparativo)}'] = dadosCombinados;
      // Marca empresa como concluída
      setState(() {
        _loadStatus[nomeEmpresa] = true;
      });
    }


    // === AJUSTE EIXO Y (referência) ===============================
    // Calcula o pico real somando todas as empresas por dia, pois cada
    // barra representa o agregado diário.
    final Map<String, double> totaisPorDia = {};
    for (final mapa in dadosPorEmpresa.values) {
      mapa.forEach((dia, valor) {
        totaisPorDia[dia] = (totaisPorDia[dia] ?? 0) + valor;
      });
    }

    final maxLocal = totaisPorDia.values.fold<double>(
      0.0, (prev, el) => el > prev ? el : prev);

    // Sobe para o próximo “nice” e adiciona 100 k de folga para a barra
    // não encostar no topo do gráfico.
    final computedMaxY = _roundUpToNice(maxLocal + 100000);

    setState(() {
      _loading = false;
      maxValor = computedMaxY;
      _computedMaxY = computedMaxY;
      _intervalY = _calculateInterval(_computedMaxY);
    });
    // ===============================================================
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
    final values = List<double>.generate(
        steps + 1, (i) => _computedMaxY - i * step);

    return SizedBox(
      width: 30,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: values
            .map((v) =>
            Text(
              formatEixoCurrency(v),
              style: const TextStyle(fontSize: 10),
            ))
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Processamento de dadosPorDia e diasOrdenados
    final diasUnicos = <String>{};
    final dadosPorDia = <String, List<double>>{};
    for (final empresa in dadosPorEmpresa.entries) {
      final dados = empresa.value;
      for (final dia in dados.entries) {
        diasUnicos.add(dia.key);
        dadosPorDia.putIfAbsent(dia.key, () => []);
        dadosPorDia[dia.key]!.add(dia.value);
      }
    }
    // Separar dias principais e comparativos para ordenar
    final diasPrincipais = diasUnicos.where((d) => !d.contains('(comparativo)')).toList();
    diasPrincipais.sort((a, b) => DateFormat('dd/MM').parse(a).compareTo(DateFormat('dd/MM').parse(b)));
    final diasComparativos = diasUnicos.where((d) => d.contains('(comparativo)')).toList();
    diasComparativos.sort((a, b) {
      // Remover o sufixo para comparar datas
      String aDate = a.replaceAll(' (comparativo)', '');
      String bDate = b.replaceAll(' (comparativo)', '');
      return DateFormat('dd/MM').parse(aDate).compareTo(DateFormat('dd/MM').parse(bDate));
    });
    // Monta diasOrdenados intercalando: para cada dia principal, buscar o comparativo correspondente
    final diasOrdenados = <String>[];
    for (final diaPrincipal in diasPrincipais) {
      diasOrdenados.add(diaPrincipal);
      final comparativo = diasComparativos.firstWhere(
            (d) => d.startsWith(diaPrincipal),
        orElse: () => '',
      );
      if (comparativo.isNotEmpty) {
        diasOrdenados.add(comparativo);
      }
    }

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
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  child: Row(
                    // === ALTERAÇÃO: alinhar texto e ícone à esquerda mantendo recuo lateral ===
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
          : Column(
        children: [
          // Vertical filters block
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.filter_alt, size: 18, color: Colors.black87),
                    label: const Text('Datas', style: TextStyle(color: Colors.black87)),
                    onPressed: _abrirFiltroDatas,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      backgroundColor: Colors.grey.shade200,
                      elevation: 0,
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
          // Title block
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Comparativo por Empresa Diário',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // Chart container
          SizedBox(
            height: _chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 16, bottom: _bottomReservedSize),
                  child: _buildFixedYAxis(height: _chartHeight - _bottomReservedSize),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _scrollControllerHorizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15), // recuo de 15 px em ambos os lados
                      child: SizedBox(
                        width: max(
                          MediaQuery.of(context).size.width,
                          diasPrincipais.length * 60.0 + 60, // 60 px por dia + margem
                        ),
                        child: BarChart(
                          BarChartData(
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                tooltipMargin: 16,
                                // === ALTERAÇÃO: tooltip com fundo branco para melhorar leitura ===
                                getTooltipColor: (group) => Colors.white,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  // Define rótulo correto para cada barra
                                  String diaLabel;
                                  if (rodIndex == 0) {
                                    // Barra verde → período principal
                                    diaLabel = diasPrincipais[group.x.toInt()];
                                  } else {
                                    // Barra cinza → período comparativo do mesmo dia
                                    diaLabel = _encontrarDiaComparativo(
                                          diasPrincipais[group.x.toInt()],
                                          dateRange!,
                                          dateRangeComparativo!,
                                        ) ??
                                        diasPrincipais[group.x.toInt()];
                                  }

                                  final valor = rod.toY;
                                  final isComparativo = rodIndex == 1;
                                  // === ALTERAÇÃO: cor do texto do tooltip comparativo igual à cor da barra cinza (shade500) ===
                                  final corTexto = isComparativo
                                      ? Colors.grey.shade700
                                      : const Color(0xFF2E7D32);

                                  return BarTooltipItem(
                                    '$diaLabel\n${formatCurrencyReal(valor)}',
                                    TextStyle(
                                      color: corTexto,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                direction: TooltipDirection.top,
                              ),
                            ),
                            gridData: FlGridData(
                              show: true,
                              horizontalInterval: _intervalY,
                              getDrawingHorizontalLine: (value) =>
                                  FlLine(
                                    color: Colors.grey.shade300,
                                    strokeWidth: 1,
                                    dashArray: [5, 5],
                                  ),
                            ),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: _bottomReservedSize,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index < diasOrdenados.length) {
                                      return SideTitleWidget(
                                        space: 6.0,
                                        child: Transform.rotate(
                                          angle: -0.6,
                                          child: Text(
                                            diasOrdenados[index],
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                        ),
                                        meta: meta,
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                    showTitles: false, reservedSize: 60),
                              ),
                              topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            minY: 0,
                            maxY: _computedMaxY,
                            // === ALINHAMENTO: recuo suave dos dois lados (não colado)
                            alignment: BarChartAlignment.spaceAround,
                            barGroups: List.generate(diasPrincipais.length, (i) {
                              final diaPrincipal = diasPrincipais[i];
                              final diaComparativo = _encontrarDiaComparativo(diaPrincipal, dateRange!, dateRangeComparativo!) ?? '';

                              final totalPrincipal = dadosPorEmpresa.values
                                  .map((m) => m[diaPrincipal] ?? 0.0)
                                  .fold(0.0, (a, b) => a + b);

                              final totalComparativo = dadosPorEmpresa.values
                                  .map((m) => m[diaComparativo] ?? 0.0)
                                  .fold(0.0, (a, b) => a + b);

                              return BarChartGroupData(
                                x: i,
                                barsSpace: 8,
                                barRods: [
                                  BarChartRodData(
                                    toY: totalPrincipal,
                                    width: 10,
                                    color: const Color(0xFF2E7D32),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  BarChartRodData(
                                    toY: totalComparativo,
                                    width: 10,
                                    color: Colors.grey.shade500,
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
          // Legend
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
    );
  }

  DateTimeRange _calcularIntervaloPorFiltro(String filtro) {
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
      default:
        return DateTimeRange(start: now, end: now);
    }
  }


  Widget _buildFiltroEmpresas() {
    return ElevatedButton.icon(
      onPressed: () async {
        final selecionadas = await showDialog<List<Empresa>>(
          context: context,
          builder: (context) {
            final List<Empresa> tempSelecionadas = [..._empresasSelecionadas];
            return StatefulBuilder(
              builder: (context, setStateDialog) {
                return AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text('Selecionar Empresas'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      children: [
                        CheckboxListTile(
                          value: _empresas.every((empresa) => tempSelecionadas.any((e) => e.id == empresa.id)),
                          title: const Text('Selecionar Todas'),
                          activeColor: const Color(0xFF2E7D32),
                          checkColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                          onChanged: (checked) {
                            setStateDialog(() {
                              if (checked == true) {
                                tempSelecionadas.clear();
                                tempSelecionadas.addAll(_empresas);
                              } else {
                                tempSelecionadas.clear();
                              }
                            });
                          },
                        ),
                        ..._empresas.map((empresa) {
                          final selecionada = tempSelecionadas.any((e) => e.id == empresa.id);
                          return CheckboxListTile(
                            value: selecionada,
                            title: Text(empresa.nome),
                            activeColor: const Color(0xFF2E7D32),
                            checkColor: Colors.white,
                            side: const BorderSide(
                                color: Color(0xFF2E7D32), width: 1.5),
                            onChanged: (checked) {
                              setStateDialog(() {
                                if (checked == true) {
                                  if (!tempSelecionadas.any((e) => e.id == empresa.id)) {
                                    tempSelecionadas.add(empresa);
                                  }
                                } else {
                                  tempSelecionadas.removeWhere((e) => e.id == empresa.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  actions: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, null),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF2E7D32),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, tempSelecionadas),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF2E7D32),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Aplicar'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );

        if (selecionadas != null) {
          setState(() {
            _empresasSelecionadas = selecionadas;
            _loading = true;
            dadosPorEmpresa.clear();
          });
          _carregarDados();
        }
      },
      icon: const Icon(Icons.business, size: 18, color: Colors.black87),
      label: Text(
        _empresasSelecionadas.isEmpty
            ? 'Todas as Empresas'
            : _empresasSelecionadas.map((e) => e.nome).join(', '),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.black87),
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.black87,
        backgroundColor: Colors.grey.shade200,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

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
                                dateRange = DateTimeRange(start: selectedDate, end: dateRange?.end ?? selectedDate);
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
                                dateRange = DateTimeRange(start: dateRange?.start ?? selectedDate, end: selectedDate);
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
                            bool isDisabled = !_validarComparativo(_filtroSelecionado, filtro);
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

  bool _validarComparativo(String filtroPrincipal, String filtroComparativo) {
    if (filtroPrincipal.toUpperCase() == 'ONTEM' && filtroComparativo.toUpperCase() == 'ONTEM') {
      return false; // Não permite comparar ontem com ontem
    }
    return true; // Permite todas as outras combinações
  }

}
String? _encontrarDiaComparativo(String diaPrincipal, DateTimeRange periodoPrincipal, DateTimeRange periodoComparativo) {
  try {
    final data = DateFormat('dd/MM').parse(diaPrincipal);
    final diferencaDias = periodoPrincipal.start.difference(periodoComparativo.start).inDays;
    final dataComparativa = data.subtract(Duration(days: diferencaDias));
    return '${DateFormat('dd/MM').format(dataComparativa)} (comparativo)';
  } catch (_) {
    return null;
  }
}
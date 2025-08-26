import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

import 'dart:async';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';

import '../../../../models/vendas/estruturamercadologica/vendas_por_divisao_model.dart';
import '../../../../repositories/vendas/estruturamercadologica/vendas_por_divisao_repository.dart';
import 'vendas_por_secao_page.dart';

class VendasPorDivisaoPage extends StatefulWidget {
  final List<Empresa> empresasSelecionadas;
  final DateTimeRange intervalo;

  const VendasPorDivisaoPage({
    super.key,
    required this.empresasSelecionadas,
    required this.intervalo,
  });

  @override
  State<VendasPorDivisaoPage> createState() => _VendasPorDivisaoPageState();
}

class _VendasPorDivisaoPageState extends State<VendasPorDivisaoPage> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');

  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final VendasPorDivisaoRepository _repository;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<VendaPorDivisaoModel> _resultados = [];
  bool _loading = true;

  // --- Cronômetro vivo ---
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  static DateTime? _globalConsultaInicio;

  // --- Histórico de tempo ---
  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoExecucao;
  double? _tempoMedioEstimado;

  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsed = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() => _cronometro = elapsed / 1000);
    });
  }

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = VendasPorDivisaoRepository(_apiClient);
    _cadLojasService = CadLojasService(_apiClient);
    _tempoRepo = TempoExecucaoRepository();
    WidgetsBinding.instance.addObserver(this);
    _inicializarDados();
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) return;
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${_empresasSelecionadas.map((e)=>e.id).join(",")}|$dias|vendas_divisao';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media  = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoExecucao = ultimo;
        _tempoMedioEstimado = media;
      });
    }
  }

  Future<void> _inicializarDados() async {
    final rawEmpresas = await _cadLojasService.getEmpresasComNome();

    /// 🔄 Remove duplicidades mantendo a última ocorrência de cada `id`
    final Map<int, Empresa> mapaEmpresas = {
      for (final emp in rawEmpresas) emp.id: emp,
    };

    /// ➕ Adiciona a opção "Todas as Empresas" se ainda não existir
    mapaEmpresas.putIfAbsent(
      0,
      () => Empresa(id: 0, nome: 'Todas as Empresas'),
    );

    final empresas = mapaEmpresas.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    setState(() {
      _empresas = empresas;

      // Garante que as selecionadas existam na lista deduplicada
      _empresasSelecionadas = widget.empresasSelecionadas
          .where((e) => mapaEmpresas.containsKey(e.id))
          .toList();

      _selectedDateRange = widget.intervalo;
    });
    await _inicializarTempoExecucao();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    _tempoExecucao = null;
    if (_globalConsultaInicio == null) {
      _cronometro = 0.0;
      _globalConsultaInicio = DateTime.now();
    }
    _startCronometro();
    final stopwatch = Stopwatch()..start();
    bool consultaNecessaria = true;
    // === AGREGAÇÃO POR DIVISÃO QUANDO HÁ MAIS DE UMA EMPRESA ===
    final Map<int, VendaPorDivisaoModel> mapaResultados = {};

    for (final empresa in _empresasSelecionadas) {
      final dados = await _repository.getVendasPorDivisao(
        idEmpresa: empresa.id,
        dataInicial: _selectedDateRange!.start,
        dataFinal: _selectedDateRange!.end,
      );

      for (final item in dados) {
        // Se já houver essa divisão no mapa, soma os valores
        if (mapaResultados.containsKey(item.idDivisao)) {
          final acumulado = mapaResultados[item.idDivisao]!;
          mapaResultados[item.idDivisao] = acumulado.copyWith(
            valTotLiquido: acumulado.valTotLiquido + item.valTotLiquido,
            lucro: acumulado.lucro + item.lucro,
          );
        } else {
          // Armazena uma cópia inicial
          mapaResultados[item.idDivisao] = item;
        }
      }
    }

    // Converte para lista e ordena pelo valor total decrescente
    final resultados = mapaResultados.values.toList()
      ..sort((a, b) => b.valTotLiquido.compareTo(a.valTotLiquido));

    // Após ordenar os resultados
    final totalGeral = resultados.fold<double>(0, (soma, e) => soma + e.valTotLiquido);

    for (final item in resultados) {
      final percVenda = totalGeral > 0 ? (item.valTotLiquido / totalGeral) * 100 : 0;
      final percLucro = item.valTotLiquido > 0 ? (item.lucro / item.valTotLiquido) * 100 : 0;
      item.percVendaTotal = percVenda.toDouble();
      item.percLucratividade = percLucro.toDouble();
    }

    stopwatch.stop();
    final tempoMs = stopwatch.elapsedMilliseconds;
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${_empresasSelecionadas.map((e)=>e.id).join(",")}|$dias|vendas_divisao';
    final tempoReal = tempoMs / 1000;
    if (consultaNecessaria) {
      await _tempoRepo.salvarTempo(chave, tempoMs);
    }
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoExecucao = tempoReal;
        _tempoMedioEstimado = media;
      });
    }
    _cronometroTimer?.cancel();
    _globalConsultaInicio = null;

    setState(() {
      _resultados = resultados;
      _loading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _carregarDados();
    }
  }

  @override
  void dispose() {
    _cronometroTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
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

  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    String _formattedDateRange() {
      if (_selectedDateRange == null) return 'Selecionar intervalo';
      final start = _formatter.format(_selectedDateRange!.start);
      final end = _formatter.format(_selectedDateRange!.end);
      return '$start - $end';
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
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
                  PopupMenuButton<Empresa>(
                    color: Colors.white,
                    itemBuilder: (context) {
                      return _empresas.map((empresa) {
                        return PopupMenuItem<Empresa>(
                          value: empresa,
                          child: Text(empresa.toString()),
                        );
                      }).toList();
                    },
                    onSelected: (empresa) {
                      setState(() {
                        _empresasSelecionadas = empresa.id == 0
                            ? _empresas.where((e) => e.id != 0).toList()
                            : [empresa];
                      });
                      _carregarDados();
                    },
                    tooltip: 'Selecionar empresa',
                    child: TextButton.icon(
                      icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                      label: Text(
                        _empresasSelecionadas.isEmpty
                            ? 'Empresa'
                            : _empresasSelecionadas.length == 1
                                ? _empresasSelecionadas.first.toString()
                                : 'Todas as Empresas',
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
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formattedDateRange()),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
             const SizedBox(height: 8), // Removido espaçador abaixo do título
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _modoBusca
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Buscar divisão...',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _termoBusca = value.toLowerCase();
                            });
                          },
                        )
                      : Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Vendas por Divisão',
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
                IconButton(
                  icon: Icon(_modoBusca ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      _modoBusca = !_modoBusca;
                      if (!_modoBusca) {
                        _searchController.clear();
                        _termoBusca = '';
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_resultados.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 32.0),
                  child: Text('Nenhum resultado encontrado.'),
                ),
              )
            else
              Builder(
                builder: (context) {
                  final filteredList = _resultados.where((e) => e.descricao.toLowerCase().contains(_termoBusca)).toList();
                  return ListView.builder(
                    itemCount: filteredList.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = filteredList[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VendasPorSecaoPage(
                                empresasSelecionadas: _empresasSelecionadas,
                                intervalo: _selectedDateRange!,
                                idDivisao: item.idDivisao,
                              ),
                            ),
                          );
                        },
                        child: _DivisaoCard(
                          titulo: item.descricao.trim(),
                          vendaFmt: 'Venda: ${currency.format(item.valTotLiquido)}',
                          lucroFmt: 'Lucro: ${currency.format(item.lucro)}',
                          percVendaFmt: '% Venda: ${item.percVendaTotal?.toStringAsFixed(2) ?? '--'}%',
                          percLucroFmt: '% Lucro: ${item.percLucratividade?.toStringAsFixed(2) ?? '--'}%',
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Card retangular no mesmo estilo do dashboard principal
class _DivisaoCard extends StatelessWidget {
  final String titulo;
  final String vendaFmt;
  final String lucroFmt;
  final String? percVendaFmt;
  final String? percLucroFmt;

  const _DivisaoCard({
    required this.titulo,
    required this.vendaFmt,
    required this.lucroFmt,
    this.percVendaFmt,
    this.percLucroFmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          )
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.paid, size: 20, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: vendaFmt,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      TextSpan(
                        text: '  ${percVendaFmt?.replaceAll("% Venda: ", "").replaceAll("%", "") ?? "--"}%',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.attach_money, size: 20, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: lucroFmt,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      TextSpan(
                        text: '  ${percLucroFmt?.replaceAll("% Lucro: ", "").replaceAll("%", "") ?? "--"}%',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Removidos os Text widgets de percVendaFmt e percLucroFmt
        ],
      ),
    );
  }
}
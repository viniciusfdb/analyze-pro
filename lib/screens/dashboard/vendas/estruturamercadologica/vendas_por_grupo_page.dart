

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

import 'dart:async';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';

import 'package:analyzepro/screens/dashboard/vendas/estruturamercadologica/vendas_por_subgrupo_page.dart';

import '../../../../models/vendas/estruturamercadologica/vendas_por_grupo_model.dart';
import '../../../../repositories/vendas/estruturamercadologica/vendas_por_grupo_repository.dart';

class VendasPorGrupoPage extends StatefulWidget {
  final List<Empresa> empresasSelecionadas;
  final DateTimeRange intervalo;
  final int? idSecao;

  const VendasPorGrupoPage({
    super.key,
    required this.empresasSelecionadas,
    required this.intervalo,
    required this.idSecao,
  });

  @override
  State<VendasPorGrupoPage> createState() => _VendasPorGrupoPageState();
}

class _VendasPorGrupoPageState extends State<VendasPorGrupoPage> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');

  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final VendasPorGrupoRepository _repository;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<VendaPorGrupoModel> _resultados = [];
  bool _loading = true;

  // --- Cronômetro vivo ---
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  static DateTime? _globalConsultaInicio;

  // --- Histórico ---
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
    _repository = VendasPorGrupoRepository(_apiClient);
    _cadLojasService = CadLojasService(_apiClient);
    _tempoRepo = TempoExecucaoRepository();
    WidgetsBinding.instance.addObserver(this);
    _inicializarDados();
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresasSelecionadas.isEmpty || _selectedDateRange == null) return;
    final dias = _selectedDateRange!.end.difference(_selectedDateRange!.start).inDays;
    final chave = '${_empresasSelecionadas.map((e)=>e.id).join(",")}|$dias|vendas_grupo';
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

    final Map<int, Empresa> mapaEmpresas = {
      for (final emp in rawEmpresas) emp.id: emp,
    };

    mapaEmpresas.putIfAbsent(
      0,
          () => Empresa(id: 0, nome: 'Todas as Empresas'),
    );

    final empresas = mapaEmpresas.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    setState(() {
      _empresas = empresas;
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
    final Map<int, VendaPorGrupoModel> mapaResultados = {};

    for (final empresa in _empresasSelecionadas) {
      final dados = await _repository.getVendasPorGrupo(
        idEmpresa: empresa.id,
        idSecao: widget.idSecao == 0 ? null : widget.idSecao,
        dataInicial: _selectedDateRange!.start,
        dataFinal: _selectedDateRange!.end,
      );

      for (final item in dados) {
        if (mapaResultados.containsKey(item.idGrupo)) {
          final acumulado = mapaResultados[item.idGrupo]!;
          mapaResultados[item.idGrupo] = acumulado.copyWith(
            valTotLiquido: acumulado.valTotLiquido + item.valTotLiquido,
            lucro: acumulado.lucro + item.lucro,
          );
        } else {
          mapaResultados[item.idGrupo] = item;
        }
      }
    }

    final resultados = mapaResultados.values.toList()
      ..sort((a, b) => b.valTotLiquido.compareTo(a.valTotLiquido));

    // Calcula total geral e percentuais
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
    final chave = '${_empresasSelecionadas.map((e)=>e.id).join(",")}|$dias|vendas_grupo';
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

  @override
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
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _modoBusca
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Buscar grupo...',
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
                                text: 'Vendas por Grupo',
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
              ListView.builder(
                itemCount: _resultados
                    .where((e) => e.descricao.toLowerCase().contains(_termoBusca))
                    .toList()
                    .length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final filteredList = _resultados
                      .where((e) => e.descricao.toLowerCase().contains(_termoBusca))
                      .toList();
                  final item = filteredList[index];
                  return _GrupoCard(
                    idGrupo: item.idGrupo,
                    titulo: item.descricao.trim(),
                    vendaFmt: 'Venda: ${currency.format(item.valTotLiquido)}',
                    lucroFmt: 'Lucro: ${currency.format(item.lucro)}',
                    empresasSelecionadas: _empresasSelecionadas,
                    intervalo: _selectedDateRange!,
                    percVenda: item.percVendaTotal,
                    percLucro: item.percLucratividade,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _GrupoCard extends StatelessWidget {
  final int idGrupo;
  final String titulo;
  final String vendaFmt;
  final String lucroFmt;
  final List<Empresa> empresasSelecionadas;
  final DateTimeRange intervalo;
  final double? percVenda;
  final double? percLucro;

  const _GrupoCard({
    required this.idGrupo,
    required this.titulo,
    required this.vendaFmt,
    required this.lucroFmt,
    required this.empresasSelecionadas,
    required this.intervalo,
    required this.percVenda,
    required this.percLucro,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VendasPorSubgrupoPage(
              empresasSelecionadas: empresasSelecionadas,
              intervalo: intervalo,
              idGrupo: idGrupo,
            ),
          ),
        );
      },
      child: Container(
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
                        if (percVenda != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: '${percVenda!.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
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
                        if (percLucro != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: '${percLucro!.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
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
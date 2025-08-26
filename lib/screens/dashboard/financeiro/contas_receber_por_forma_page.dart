
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'contas_receber_vencimento_detalhado_page.dart';

import '../../../api/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../services/cad_lojas_service.dart';
import '../../../models/cadastros/cad_lojas.dart';

class ContasReceberPorFormaPage extends StatefulWidget {
  final List<Empresa> empresasSelecionadas;
  final DateTimeRange intervalo;

  const ContasReceberPorFormaPage({
    super.key,
    required this.empresasSelecionadas,
    required this.intervalo,
  });

  @override
  State<ContasReceberPorFormaPage> createState() => _ContasReceberPorFormaPageState();
}

class _ContasReceberPorFormaPageState extends State<ContasReceberPorFormaPage> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');

  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<_FormaResumo> _resultados = [];
  bool _loading = true;

  // --- Cronômetro vivo ---
  Timer? _cronometroTimer;
  double _cronometro = 0.0;
  static DateTime? _globalConsultaInicio;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _cadLojasService = CadLojasService(_apiClient);
    WidgetsBinding.instance.addObserver(this);
    _inicializarDados();
    _searchController.addListener(() => setState(() {}));
  }

  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsed = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() => _cronometro = elapsed / 1000);
    });
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

    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    if (_globalConsultaInicio == null) {
      _cronometro = 0.0;
      _globalConsultaInicio = DateTime.now();
    }
    _startCronometro();

    try {
      final Map<String, _FormaResumo> acc = {};

      for (final empresa in _empresasSelecionadas) {
        final dados = await _carregarDetalhesEmpresa(empresa.id);
        for (final item in dados) {
          final idrec = (item['idrecebimento'] as num?)?.toInt() ?? 0;
          final descrrec = (item['descrrecebimento'] ?? '').toString();
          final key = '$idrec|$descrrec';
          final valor = (item['valliquidotitulo'] as num?)?.toDouble() ?? 0.0;

          final atual = acc[key] ?? _FormaResumo(
            idRecebimento: idrec,
            descricao: descrrec.isNotEmpty ? descrrec : '—',
            total: 0.0,
            qtdTitulos: 0,
          );
          acc[key] = atual.copyWith(
            total: atual.total + valor,
            qtdTitulos: atual.qtdTitulos + 1,
          );
        }
      }

      final resultados = acc.values.toList()..sort((a,b)=>b.total.compareTo(a.total));
      setState(() {
        _resultados = resultados;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('❌ Erro ao carregar dados: $e');
    } finally {
      _cronometroTimer?.cancel();
      _globalConsultaInicio = null;
    }
  }

  Future<List<Map<String, dynamic>>> _carregarDetalhesEmpresa(int idEmpresa) async {
    final body = {
      'page': 1,
      'limit': 1000,
      'clausulas': [
        {'campo': 'ra_idempresa', 'valor': idEmpresa, 'operador': 'IGUAL'},
        {
          'campo': 'ra_dtini',
          'valor': DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start),
          'operador': 'IGUAL',
          'operadorLogico': 'AND',
        },
        {
          'campo': 'ra_dtfim',
          'valor': DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end),
          'operador': 'IGUAL',
          'operadorLogico': 'AND',
        },
      ],
    };

    try {
      final resp = await _apiClient.postService('insights/contas_receber_vencimento_detalhado', body: body);
      final data = resp['data'];
      if (data is List) return data.cast<Map<String, dynamic>>();
      return <Map<String, dynamic>>[];
    } catch (e) {
      debugPrint('❌ erro carregarDetalhesEmpresa($idEmpresa): $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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

  String _formattedDateRange() {
    if (_selectedDateRange == null) return 'Selecionar intervalo';
    final start = _formatter.format(_selectedDateRange!.start);
    final end = _formatter.format(_selectedDateRange!.end);
    return '$start - $end';
  }

  String _fmtMoney(num v) => NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final totalGeral = _resultados.fold<double>(0.0, (s, e) => s + e.total);

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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _modoBusca
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Buscar forma...',
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
                                text: 'A Receber por Forma de Pgto',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: '  ${_cronometro.toStringAsFixed(1)}s',
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
                  final filtered = _resultados.where((e) => e.descricao.toLowerCase().contains(_termoBusca)).toList();
                  final totalGeralLocal = filtered.fold<double>(0.0, (s, e) => s + e.total);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (filtered.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'Total Geral: ' + _fmtMoney(totalGeralLocal),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ListView.builder(
                        itemCount: filtered.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final perc = totalGeralLocal > 0 ? (item.total / totalGeralLocal) * 100 : 0.0;
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ContasReceberVencimentoDetalhadoPage(
                                    empresasSelecionadas: _empresasSelecionadas,
                                    intervalo: _selectedDateRange!,
                                    idRecebimento: item.idRecebimento,
                                  ),
                                ),
                              );
                            },
                            child: _FormaCard(
                              titulo: item.descricao.trim(),
                              totalFmt: 'Total: ${currency.format(item.total)}',
                              qtdFmt: 'Títulos: ${item.qtdTitulos}',
                              percFmt: '% Total: ${perc.toStringAsFixed(2)}%',
                            ),
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

/// Card retangular no mesmo estilo do dashboard principal (espelhando _DivisaoCard)
class _FormaCard extends StatelessWidget {
  final String titulo;
  final String totalFmt;
  final String qtdFmt;
  final String? percFmt;

  const _FormaCard({
    required this.titulo,
    required this.totalFmt,
    required this.qtdFmt,
    this.percFmt,
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
                        text: totalFmt,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      TextSpan(
                        text: '  ${percFmt?.replaceAll('% Total: ', '').replaceAll('%', '') ?? "--"}%',
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
              const Icon(Icons.receipt_long, size: 20, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  qtdFmt,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormaResumo {
  final int idRecebimento;
  final String descricao;
  final double total;
  final int qtdTitulos;

  const _FormaResumo({
    required this.idRecebimento,
    required this.descricao,
    required this.total,
    required this.qtdTitulos,
  });

  _FormaResumo copyWith({
    int? idRecebimento,
    String? descricao,
    double? total,
    int? qtdTitulos,
  }) => _FormaResumo(
        idRecebimento: idRecebimento ?? this.idRecebimento,
        descricao: descricao ?? this.descricao,
        total: total ?? this.total,
        qtdTitulos: qtdTitulos ?? this.qtdTitulos,
      );
}

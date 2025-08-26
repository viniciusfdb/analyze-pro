import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../api/api_client.dart';
import '../../../../models/vendas/estruturamercadologica/vendas_por_vendedor_secao_model.dart';
import '../../../../repositories/vendas/estruturamercadologica/vendas_por_vendedor_secao_repository.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/cad_lojas_service.dart';
import '../../../../models/cadastros/cad_lojas.dart';
import 'vendas_por_vendedor_grupo_page.dart';

class VendasPorVendedorSecaoPage extends StatefulWidget {
  final int idEmpresa;
  final int idVendedor;
  final int? idDivisao;
  final DateTime dataInicial;
  final DateTime dataFinal;

  const VendasPorVendedorSecaoPage({
    Key? key,
    required this.idEmpresa,
    required this.idVendedor,
    this.idDivisao,
    required this.dataInicial,
    required this.dataFinal,
  }) : super(key: key);

  @override
  State<VendasPorVendedorSecaoPage> createState() => _VendasPorVendedorSecaoPageState();
}

class _VendasPorVendedorSecaoPageState extends State<VendasPorVendedorSecaoPage> {
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;

  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final VendasPorVendedorSecaoRepository _repository;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<VendaPorVendedorSecaoModel> _resultados = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = VendasPorVendedorSecaoRepository(_apiClient);
    _cadLojasService = CadLojasService(_apiClient);
    _inicializarDados();
  }

  Future<void> _inicializarDados() async {
    final rawEmpresas = await _cadLojasService.getEmpresasComNome();
    final Map<int, Empresa> mapaEmpresas = {
      for (final emp in rawEmpresas) emp.id: emp,
    };
    mapaEmpresas.putIfAbsent(0, () => Empresa(id: 0, nome: 'Todas as Empresas'));

    final empresas = mapaEmpresas.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    setState(() {
      _empresas = empresas;
      _empresasSelecionadas = _empresas.where((e) => e.id == widget.idEmpresa).toList();
      _selectedDateRange = DateTimeRange(start: widget.dataInicial, end: widget.dataFinal);
    });

    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    final List<VendaPorVendedorSecaoModel> resultados = [];

    for (final empresa in _empresasSelecionadas) {
      final dados = await _repository.getVendasPorVendedorSecao(
        idEmpresa: empresa.id,
        idVendedor: widget.idVendedor,
        idDivisao: widget.idDivisao,
        dataInicial: _selectedDateRange!.start,
        dataFinal: _selectedDateRange!.end,
      );
      resultados.addAll(dados);
    }

    resultados.sort((a, b) => b.valTotLiquido.compareTo(a.valTotLiquido));

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
    _searchController.dispose();
    super.dispose();
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
                        _empresasSelecionadas = [empresa];
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
                            hintText: 'Buscar seção...',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _termoBusca = value.toLowerCase();
                            });
                          },
                        )
                      : const Text(
                          'Vendas por Vendedor (Seção)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            const SizedBox(height: 2),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.only(top: 32.0), child: CircularProgressIndicator()))
            else if (_resultados.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.only(top: 32.0), child: Text('Nenhum resultado encontrado.')))
            else
              Builder(
                builder: (context) {
                  final listaFiltrada = _resultados.where((e) => e.descricao.toLowerCase().contains(_termoBusca)).toList();
                  return ListView.builder(
                    itemCount: listaFiltrada.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = listaFiltrada[index];
                      final percVenda = item.percVenda.toStringAsFixed(1);
                      final percLucro = item.percLucro.toStringAsFixed(1);
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VendasPorVendedorGrupoPage(
                                idEmpresa: _empresasSelecionadas.first.id,
                                idVendedor: widget.idVendedor,
                                idSecao: item.idSecao,
                                dataInicial: _selectedDateRange!.start,
                                dataFinal: _selectedDateRange!.end,
                              ),
                            ),
                          );
                        },
                        child: _SecaoCard(
                          titulo: item.descricao.trim(),
                          vendaFmt: 'Venda: ${currency.format(item.valTotLiquido)}',
                          lucroFmt: 'Lucro: ${currency.format(item.lucro)}',
                          percVendaFmt: '% Venda: $percVenda%',
                          percLucroFmt: '% Lucro: $percLucro%',
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

class _SecaoCard extends StatelessWidget {
  final String titulo;
  final String vendaFmt;
  final String lucroFmt;
  final String? percVendaFmt;
  final String? percLucroFmt;

  const _SecaoCard({
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
                      if (percVendaFmt != null) ...[
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: '${percVendaFmt!.replaceAll("% Venda: ", "").replaceAll("%", "")}%',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ],
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
                      if (percLucroFmt != null) ...[
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: '${percLucroFmt!.replaceAll("% Lucro: ", "").replaceAll("%", "")}%',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
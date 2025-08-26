import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../api/api_client.dart';
import '../../../../services/auth_service.dart';
import '../../../../models/financeiro/contas_receber_vencimento_detalhado.dart';
import '../../../models/cadastros/cad_lojas.dart';
import '../../../repositories/financeiro/contas_receber_vencimento_detalhado_repository.dart';
import '../../../../services/cad_lojas_service.dart';

class ContasReceberVencimentoDetalhadoPage extends StatefulWidget {
  final List<Empresa> empresasSelecionadas;
  final DateTimeRange intervalo;
  final int? idRecebimento;

  const ContasReceberVencimentoDetalhadoPage({
    Key? key,
    required this.empresasSelecionadas,
    required this.intervalo,
    this.idRecebimento,
  }) : super(key: key);

  @override
  State<ContasReceberVencimentoDetalhadoPage> createState() => _ContasReceberVencimentoDetalhadoPageState();
}

class _ContasReceberVencimentoDetalhadoPageState extends State<ContasReceberVencimentoDetalhadoPage> {
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final ContasReceberVencimentoDetalhadoRepository _repository;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<ContasReceberVencimentoDetalhadoModel> _resultados = [];
  bool _loading = true;

  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = ContasReceberVencimentoDetalhadoRepository(_apiClient);
    _cadLojasService = CadLojasService(_apiClient);
    _inicializarDados();
  }

  Future<void> _inicializarDados() async {
    final rawEmpresas = await _cadLojasService.getEmpresasComNome();
    final Map<int, Empresa> mapaEmpresas = {for (final emp in rawEmpresas) emp.id: emp};
    mapaEmpresas.putIfAbsent(0, () => Empresa(id: 0, nome: 'Todas as Empresas'));
    final empresas = mapaEmpresas.values.toList()..sort((a, b) => a.id.compareTo(b.id));

    setState(() {
      _empresas = empresas;
      _empresasSelecionadas = widget.empresasSelecionadas
          .where((e) => mapaEmpresas.containsKey(e.id))
          .toList();
      _selectedDateRange = widget.intervalo;
    });

    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    final Map<int, List<ContasReceberVencimentoDetalhadoModel>> mapa = {};

    for (final empresa in _empresasSelecionadas) {
      final dados = await _repository.getDetalhamento(
        idEmpresa: empresa.id,
        dataInicial: _selectedDateRange!.start,
        dataFinal: _selectedDateRange!.end,
        idRecebimento: widget.idRecebimento,
      );

      for (final item in dados) {
        mapa.putIfAbsent(item.idClifor, () => []).add(item);
      }
    }

    // Ordena os clientes pelo total líquido decrescente
    final listaOrdenada = mapa.entries.toList()
      ..sort((a, b) {
        final totalB = b.value.fold<double>(0.0, (soma, item) => soma + item.valLiquidoTitulo);
        final totalA = a.value.fold<double>(0.0, (soma, item) => soma + item.valLiquidoTitulo);
        return totalB.compareTo(totalA);
      });

    setState(() {
      _resultados = listaOrdenada.expand((e) => e.value).toList();
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

  void _mostrarDetalhes(List<ContasReceberVencimentoDetalhadoModel> titulos, String nome) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (_) {
        final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...titulos.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Título ${item.idTitulo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.paid, 'Valor Bruto', currency.format(item.valTitulo)),
                    _buildInfoRow(Icons.attach_money, 'Valor Líquido', currency.format(item.valLiquidoTitulo)),
                    _buildInfoRow(Icons.event, 'Vencimento', DateFormat('dd/MM/yyyy').format(item.dtVencimento)),
                    _buildInfoRow(Icons.receipt_long, 'Recebimento', item.descrRecebimento),
                    if (item.obstitulo.trim().isNotEmpty)
                      _buildInfoRow(Icons.note_alt, 'Observação', item.obstitulo),
                  ],
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
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

    final agrupado = <int, List<ContasReceberVencimentoDetalhadoModel>>{};
    for (final item in _resultados) {
      agrupado.putIfAbsent(item.idClifor, () => []).add(item);
    }

    final listaFiltrada = agrupado.entries
        .where((e) => e.value.first.nome.toLowerCase().contains(_termoBusca))
        .toList();

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
                      hintText: 'Buscar cliente...',
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _termoBusca = value.toLowerCase();
                      });
                    },
                  )
                      : const Text(
                    'Contas a Receber Detalhado',
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
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (listaFiltrada.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 32.0),
                  child: Text('Nenhum resultado encontrado.'),
                ),
              )
            else
              ListView.builder(
                itemCount: listaFiltrada.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final cliente = listaFiltrada[index].value.first;
                  final total = listaFiltrada[index].value.fold<double>(0.0, (soma, item) => soma + item.valLiquidoTitulo);

                  return GestureDetector(
                    onTap: () => _mostrarDetalhes(listaFiltrada[index].value, cliente.nome),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 8),
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
                            cliente.nome,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.paid, size: 20, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 6),
                              Text(
                                'Total: ${currency.format(total)}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
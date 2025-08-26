

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

import '../../../../models/vendas/estruturamercadologica/vendas_por_vendedor_produto_model.dart';
import '../../../../repositories/vendas/estruturamercadologica/vendas_por_vendedor_produto_repository.dart';

class VendasPorVendedorProdutoPage extends StatefulWidget {
  final int idEmpresa;
  final int idVendedor;
  final int idSubgrupo;
  final DateTime dataInicial;
  final DateTime dataFinal;

  const VendasPorVendedorProdutoPage({
    super.key,
    required this.idEmpresa,
    required this.idVendedor,
    required this.idSubgrupo,
    required this.dataInicial,
    required this.dataFinal,
  });

  @override
  State<VendasPorVendedorProdutoPage> createState() => _VendasPorVendedorProdutoPageState();
}

class _VendasPorVendedorProdutoPageState extends State<VendasPorVendedorProdutoPage> {
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');
  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;

  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final VendasPorVendedorProdutoRepository _repository;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<VendaPorVendedorProdutoModel> _resultados = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = VendasPorVendedorProdutoRepository(_apiClient);
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

    // 1) Coleta dados de todas as empresas selecionadas -----------------------
    final List<VendaPorVendedorProdutoModel> resultados = [];
    for (final empresa in _empresasSelecionadas) {
      final dados = await _repository.getVendasPorVendedorProduto(
        idEmpresa: empresa.id,
        idVendedor: widget.idVendedor,
        idSubgrupo: widget.idSubgrupo,
        dataInicial: _selectedDateRange!.start,
        dataFinal: _selectedDateRange!.end,
      );
      resultados.addAll(dados);
    }

    // 2) Agrupa registros duplicados somando valores --------------------------
    final Map<int, VendaPorVendedorProdutoModel> agrupados = {};
    for (final item in resultados) {
      final chave = item.idSubProduto; // agrupa por variação (subproduto)

      if (agrupados.containsKey(chave)) {
        final existente = agrupados[chave]!;
        agrupados[chave] = existente.copyWith(
          qtdProduto: existente.qtdProduto + item.qtdProduto,
          qtdProdutoVenda: existente.qtdProdutoVenda + item.qtdProdutoVenda,
          valTotLiquido: existente.valTotLiquido + item.valTotLiquido,
          lucro: existente.lucro + item.lucro,
        );
      } else {
        agrupados[chave] = item;
      }
    }

    // 3) Recalcula percentuais após o somatório -------------------------------
    final double totalVendaGeral =
        agrupados.values.fold<double>(0, (soma, e) => soma + e.valTotLiquido);

    final List<VendaPorVendedorProdutoModel> listaAgrupada =
        agrupados.values.map((e) {
      final percVendaCalc =
          totalVendaGeral == 0 ? 0 : e.valTotLiquido * 100 / totalVendaGeral;
      final percLucroCalc =
          e.valTotLiquido == 0 ? 0 : e.lucro * 100 / e.valTotLiquido;

      return e.copyWith(
        percVendaTotal: percVendaCalc.toDouble(),
        percLucratividade: percLucroCalc.toDouble(),
      );
    }).toList()
      ..sort((a, b) => b.valTotLiquido.compareTo(a.valTotLiquido));

    // 4) Atualiza estado ------------------------------------------------------
    if (mounted) {
      setState(() {
        _resultados = listaAgrupada;
        _loading = false;
      });
    }
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
                            hintText: 'Buscar produto...',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _termoBusca = value.toLowerCase();
                            });
                          },
                        )
                      : const Text(
                          'Vendas por Vendedor (Produto)',
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
                      return _ProdutoCard(produto: item);
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

class _ProdutoCard extends StatelessWidget {
  final VendaPorVendedorProdutoModel produto;

  const _ProdutoCard({required this.produto});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.descricao.trim(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(Icons.numbers, 'Produto', produto.idProduto.toString()),
                    _buildInfoRow(Icons.category, 'Subproduto', produto.idSubProduto.toString()),
                    _buildInfoRow(Icons.shopping_cart_outlined, 'Vendido', produto.qtdProdutoVenda.toStringAsFixed(2)),
                    _buildInfoRow(Icons.paid, 'Total', currency.format(produto.valTotLiquido)),
                    _buildInfoRow(Icons.attach_money, 'Lucro', currency.format(produto.lucro)),
                    _buildInfoRow(Icons.block, 'Compra Inativa?', produto.flagInativoCompra == 'S' ? 'Sim' : 'Não'),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Fechar',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
              produto.descricao.trim(),
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
                          text: 'Venda: ${currency.format(produto.valTotLiquido)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                        ),
                        if (produto.percVendaTotal != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: '${produto.percVendaTotal!.toStringAsFixed(1)}%',
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
                          text: 'Lucro: ${currency.format(produto.lucro)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                        ),
                        if (produto.percLucratividade != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: '${produto.percLucratividade!.toStringAsFixed(1)}%',
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
      ),
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
}
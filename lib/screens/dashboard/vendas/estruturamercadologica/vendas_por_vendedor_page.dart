import 'package:analyzepro/screens/dashboard/vendas/estruturamercadologica/vendas_por_vendedor_divisao_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/estruturamercadologica/vendas_por_vendedor_secao_page.dart';
import 'package:analyzepro/screens/dashboard/vendas/estruturamercadologica/vendas_por_vendedor_grupo_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

import '../../../../models/vendas/estruturamercadologica/vendas_por_vendedor_model.dart';
import '../../../../repositories/vendas/estruturamercadologica/vendas_por_vendedor_repository.dart';

class VendasPorVendedorPage extends StatefulWidget {
  final List<Empresa> empresasSelecionadas;
  final DateTimeRange intervalo;

  const VendasPorVendedorPage({
    super.key,
    required this.empresasSelecionadas,
    required this.intervalo,
  });

  @override
  State<VendasPorVendedorPage> createState() => _VendasPorVendedorPageState();
}

class _VendasPorVendedorPageState extends State<VendasPorVendedorPage> {
  final DateFormat _formatter = DateFormat('dd/MM/yyyy');

  late final AuthService _authService;
  late final ApiClient _apiClient;
  late final VendasPorVendedorRepository _repository;
  late final CadLojasService _cadLojasService;

  List<Empresa> _empresas = [];
  List<Empresa> _empresasSelecionadas = [];
  DateTimeRange? _selectedDateRange;
  List<VendaPorVendedorModel> _resultados = [];
  bool _loading = true;

  final TextEditingController _searchController = TextEditingController();
  String _termoBusca = '';
  bool _modoBusca = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _apiClient = ApiClient(_authService);
    _repository = VendasPorVendedorRepository(_apiClient);
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
    final Map<int, VendaPorVendedorModel> mapaResultados = {};

    for (final empresa in _empresasSelecionadas) {
      final dados = await _repository.getVendasPorVendedor(
        idEmpresa: empresa.id,
        dataInicial: _selectedDateRange!.start,
        dataFinal: _selectedDateRange!.end,
      );

      for (final item in dados) {
        if (mapaResultados.containsKey(item.idVendedor)) {
          final acumulado = mapaResultados[item.idVendedor]!;
          mapaResultados[item.idVendedor] = acumulado.copyWith(
            totalVenda: acumulado.totalVenda + item.totalVenda,
            lucro: acumulado.lucro + item.lucro,
          );
        } else {
          mapaResultados[item.idVendedor] = item;
        }
      }
    }

    final resultados = mapaResultados.values.toList()
      ..sort((a, b) => b.totalVenda.compareTo(a.totalVenda));

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
                            hintText: 'Buscar vendedor...',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _termoBusca = value.toLowerCase();
                            });
                          },
                        )
                      : const Text(
                          'Vendas por Vendedor',
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
                  final listaFiltrada = _resultados.where((e) => e.nome.toLowerCase().contains(_termoBusca)).toList();
                  return ListView.builder(
                    itemCount: listaFiltrada.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = listaFiltrada[index];
                      return _VendedorCard(
                        nome: item.nome,
                        vendaFmt: 'Venda: ${currency.format(item.totalVenda)}',
                        lucroFmt: 'Lucro: ${currency.format(item.lucro)}',
                        percLucro: item.percLucratividade,
                        onTap: () {
                          if (item.idVendedor == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Não é possível afunilar em vendas sem vendedor.')),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VendasPorVendedorDivisaoPage(
                                empresasSelecionadas: _empresasSelecionadas,
                                intervalo: _selectedDateRange!,
                                idVendedor: item.idVendedor,
                              ),
                            ),
                          );
                        },
                        onLongPress: () {
                          if (item.idVendedor == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Não é possível afunilar em vendas sem vendedor.')),
                            );
                            return;
                          }
                          showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (context) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _NavigationOptionCard(
                                      icon: Icons.view_module,
                                      label: 'Por Divisão',
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VendasPorVendedorDivisaoPage(
                                              empresasSelecionadas: _empresasSelecionadas,
                                              intervalo: _selectedDateRange!,
                                              idVendedor: item.idVendedor,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    _NavigationOptionCard(
                                      icon: Icons.list_alt,
                                      label: 'Por Seção',
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VendasPorVendedorSecaoPage(
                                              idEmpresa: _empresasSelecionadas.first.id,
                                              idVendedor: item.idVendedor,
                                              idDivisao: null,
                                              dataInicial: _selectedDateRange!.start,
                                              dataFinal: _selectedDateRange!.end,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    _NavigationOptionCard(
                                      icon: Icons.layers,
                                      label: 'Por Grupo',
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VendasPorVendedorGrupoPage(
                                              idEmpresa: _empresasSelecionadas.first.id,
                                              idVendedor: item.idVendedor,
                                              idSecao: null,
                                              dataInicial: _selectedDateRange!.start,
                                              dataFinal: _selectedDateRange!.end,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
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

class _VendedorCard extends StatelessWidget {
  final String nome;
  final String vendaFmt;
  final String lucroFmt;
  final double? percLucro;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _VendedorCard({
    required this.nome,
    required this.vendaFmt,
    required this.lucroFmt,
    this.percLucro,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
              nome,
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
                        if (percLucro != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: '${percLucro!.toStringAsFixed(1)}%',
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
}
class _NavigationOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavigationOptionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Icon(icon, size: 28, color: Colors.green.shade700),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              )
            ],
          ),
        ),
      ),
    );
  }
}
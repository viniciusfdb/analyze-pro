import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../repositories/taxa_administradora_repository.dart';
import '../../models/taxa_administradora.dart';
import '../../api/api_client.dart';
import '../../services/cad_administradoras_service.dart';
import '../../services/cad_lojas_service.dart';

class TaxaAdministradoraScreen extends StatefulWidget {
  final TaxaAdministradoraRepository taxaAdministradoraRepository;
  final ApiClient apiClient;

  const TaxaAdministradoraScreen({
    super.key,
    required this.taxaAdministradoraRepository,
    required this.apiClient,
  });


  @override
  _TaxaAdministradoraScreenState createState() => _TaxaAdministradoraScreenState();
}

class _TaxaAdministradoraScreenState extends State<TaxaAdministradoraScreen> {
  late CadLojasService _cadLojasService;
  late CadAdministradorasService _cadAdministradorasService;

  int? _selectedEmpresa;
  String _dataInicial = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
  String _dataFinal = DateFormat('yyyy-MM-dd').format(DateTime.now());

  int? _selectedAdministradora;
  int? _selectedBandeira;

  List<int> _empresasDisponiveis = [];
  List<TaxaAdministradora> _dados = [];

  List<Map<String, dynamic>> _administradorasDisponiveis = [];


  bool _filtersVisible = true;
  bool _isLoading = false;

  double _totalDiferencaPositiva = 0.0;
  double _totalDiferencaNegativa = 0.0;

  @override
  void initState() {
    super.initState();
    _cadLojasService = CadLojasService(widget.apiClient);
    _cadAdministradorasService = CadAdministradorasService(widget.apiClient);
    _loadEmpresas();
    _loadAdministradoras();
  }

  /// **📌 Converte a data do formato da API (YYYY-MM-DD) para exibição (DD/MM/YYYY)**
  String _formatarDataParaExibicao(String data) {
    try {
      DateTime parsedDate = DateTime.parse(data);
      return DateFormat('dd/MM/yyyy').format(parsedDate);
    } catch (e) {
      return data; // Caso ocorra erro, retorna a string original
    }
  }

  /// **📌 Converte a data do formato exibido (DD/MM/YYYY) para o formato da API (YYYY-MM-DD)**
  String _formatarDataParaApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _loadEmpresas() async {
    List<int> empresas = await _cadLojasService.getEmpresasDisponiveis();
    setState(() {
      _empresasDisponiveis = empresas;
      if (empresas.isNotEmpty) {
        _selectedEmpresa = empresas.first;
      }
    });
  }

  /// 🔹 Carrega as administradoras da API corretamente
  Future<void> _loadAdministradoras() async {
    try {
      List<Map<String, dynamic>> administradoras =
      await _cadAdministradorasService.getAdministradorasDisponiveis();

      setState(() {
        _administradorasDisponiveis = administradoras;
      });

      debugPrint("📌 Administradoras carregadas: ${_administradorasDisponiveis
          .length}");
    } catch (e) {
      debugPrint("⚠️ Erro ao carregar administradoras: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Erro ao carregar administradoras. Tente novamente mais tarde."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _buscarDados() async {
    if (_selectedEmpresa == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecione uma empresa")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _totalDiferencaNegativa = 0.0;
      _totalDiferencaPositiva = 0.0;
    });

    List<TaxaAdministradora> allData = [];
    int currentPage = 1;
    const int limit = 100;

    try {
      bool hasMoreData = true;
      while (hasMoreData) {
        final response = await widget.taxaAdministradoraRepository.getTaxaAdministradora(
          empresa: _selectedEmpresa!,
          dataInicial: _dataInicial,
          dataFinal: _dataFinal,
          administradora: _selectedAdministradora,
          bandeira: _selectedBandeira,
          page: currentPage, // Passando a página atual
          limit: limit,      // Passando o limite
        );

        // Adiciona os dados da página atual à lista
        allData.addAll(response);

        // Verifica se há mais dados (baseado no limite da página)
        if (response.length < limit) {
          hasMoreData = false;  // Não há mais dados, para a busca
        } else {
          currentPage++;  // Aumenta o número da página para a próxima requisição
        }
      }

      // Verifica se a lista de dados está vazia
      if (allData.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Nenhum dado encontrado")),
        );
        return;  // Interrompe a execução, já que não há dados
      }

      // 🔹 Ordena os dados pelo DIF (decrescente)
      allData.sort((a, b) => b.dif.compareTo(a.dif));

      // 🔹 Cálculo das diferenças acumuladas em valores reais
      double totalNegativo = 0.0;
      double totalPositivo = 0.0;

      for (var item in allData) {
        double diferenca = item.valLiquidoPago - item.valLiquidoEsperado;

        if (diferenca < 0) {
          totalNegativo += diferenca.abs(); // Acumula diferença negativa
        } else if (diferenca > 0) {
          totalPositivo += diferenca; // Acumula diferença positiva
        }
      }

      setState(() {
        _dados = allData;
        _totalDiferencaNegativa = totalNegativo;
        _totalDiferencaPositiva = totalPositivo;
        _isLoading = false;
        _filtersVisible = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao buscar dados: ${e.toString()}")),
      );
    }
  }


  Future<void> _pickEmpresa() async {
    int? selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text("Selecione a Empresa"),
          children: _empresasDisponiveis.map((e) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e),
              child: Text("Empresa $e", style: const TextStyle(fontSize: 20)),
            );
          }).toList(),
        );
      },
    );
    if (selected != null) {
      setState(() {
        _selectedEmpresa = selected;
      });
    }
  }

  Future<void> _pickAdministradora() async {
    int? selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text("Selecione a Administradora",
              style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _administradorasDisponiveis.length,
              itemBuilder: (context, index) {
                final adm = _administradorasDisponiveis[index];
                return ListTile(
                  title: Text(adm['descricao'],
                      style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, adm['id']),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedAdministradora = selected;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Taxa Administradora"),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _filtersVisible
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filtro: Empresa
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _pickEmpresa,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _selectedEmpresa != null
                                  ? "Empresa: $_selectedEmpresa"
                                  : "Selecione a Empresa",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.filter_list, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                  // Filtro: Administradora
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _pickAdministradora,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _selectedAdministradora != null
                                  ? "${_administradorasDisponiveis.firstWhere(
                                      (adm) =>
                                  adm['id'] == _selectedAdministradora,
                                  orElse: () =>
                                  {
                                    'descricao': 'Desconhecida'
                                  })['descricao']}"
                                  : "Administradora",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.filter_list, color: Colors.white),
                        ],
                      ),
                    ),
                  ),

                  // Filtro: Data Inicial e Data Final
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: "Data Inicial",
                              labelStyle: TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                            controller: TextEditingController(
                                text: _formatarDataParaExibicao(_dataInicial),
                            ),
                            readOnly: true,
                            onTap: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.parse(_dataInicial), // ✅ Conversão para DateTime
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() {
                                  _dataInicial = _formatarDataParaApi(picked); // ✅ Armazena no formato da API
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: "Data Final",
                              labelStyle: TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                            controller: TextEditingController(
                              text: _formatarDataParaExibicao(_dataFinal), // ✅ Exibe a data formatada
                            ),
                            readOnly: true,
                            onTap: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.parse(_dataFinal), // ✅ Conversão para DateTime
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setState(() {
                                  _dataFinal = _formatarDataParaApi(picked); // ✅ Armazena no formato da API
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botão Buscar
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Center(
                      child: SizedBox(
                        width: 250,
                        child: ElevatedButton(
                          onPressed: _buscarDados,
                          child: const Text("Buscar"),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.black,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40, vertical: 15),
                            textStyle: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w400),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
                : const SizedBox(),
          ),
          if (!_filtersVisible)
            Column(
              children: [
                const SizedBox(height: 15),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _filtersVisible = true;
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            "Abrir filtros",
                            style: TextStyle(fontSize: 18,
                                fontWeight: FontWeight.w400,
                                color: Colors.white),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.expand_more, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
// Indicador de carregamento ou exibição dos dados
          _isLoading
              ? const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
              : Expanded(
            child: _dados.isEmpty
                ? const Center(child: Text(
                "Cadastre as taxas no sistema para comparar!"))
                : Column(
              children: [
                // 🔹 Exibição dos totalizadores no topo
                Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: Container(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Pago a maior: ${NumberFormat.simpleCurrency(locale: 'pt_BR').format(_totalDiferencaNegativa)}",
                        style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Pago a menor: ${NumberFormat.simpleCurrency(locale: 'pt_BR').format(_totalDiferencaPositiva)}",
                        style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                ),

                // 🔹 Lista de resultados
                Expanded(
                  child: ListView.builder(
                    itemCount: _dados.length,
                    itemBuilder: (context, index) {
                      final item = _dados[index];
                      return Card(
                        color: Colors.black,
                        margin: const EdgeInsets.all(8),
                        child: ListTile(
                          title: Text(
                            "${item.dtMovimento}",
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Produto: ${item.descrInstituicao}",
                                  style: const TextStyle(
                                      color: Colors.white70)),
                              Text(
                                  "Administradora: ${item.descrAdministradora}",
                                  style: const TextStyle(
                                      color: Colors.white70)),
                              Text(
                                "Diferença: ${NumberFormat.simpleCurrency(locale: 'pt_BR').format(item.dif)}",
                                style: TextStyle(
                                  color: item.dif > 0 ? Colors.green : Colors
                                      .red,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _mostrarDetalhes(item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

// 🔹 Ajustado para exibir os detalhes corretamente
  void _mostrarDetalhes(TaxaAdministradora item) {
    showDialog(
      context: context,
      builder: (context) {
        double diferenca = item.valLiquidoPago - item.valLiquidoEsperado; // Calculando a diferença antes de passar para o _buildDetailRow
        return AlertDialog(
          title: Text("Detalhes - ${item.dtMovimento}"),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow("Administradora", item.descrAdministradora),
                _buildDetailRow("Bandeira", item.idBandeira.toString()),
                _buildDetailRow("Taxa de Cadastro", "${item.taxaCadastro.toStringAsFixed(2)}%"),
                _buildDetailRow("Taxa de Administração", "${item.taxaAdm.toStringAsFixed(2)}%"),
                _buildDetailRow("Valor Bruto", "${NumberFormat.simpleCurrency(locale: 'pt_BR').format(item.valTitulo)}"),
                _buildDetailRow("Valor Líquido Esperado", "${NumberFormat.simpleCurrency(locale: 'pt_BR').format(item.valLiquidoEsperado)}"),
                _buildDetailRow("Valor Líquido Pago", "${NumberFormat.simpleCurrency(locale: 'pt_BR').format(item.valLiquidoPago)}"),
                _buildDetailRow(
                  "Diferença",
                  "${NumberFormat.simpleCurrency(locale: 'pt_BR').format(diferenca)}",
                  isHighlighted: diferenca < 0, // Diferença negativa será vermelha
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fechar"),
            ),
          ],
        );
      },
    );
  }


// 🔹 Método para exibir os valores corretamente formatados
  Widget _buildDetailRow(String label, String value,
      {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
              label, style: const TextStyle(color: Colors.white, fontSize: 16)),
          Text(
            value,
            style: TextStyle(
              color: isHighlighted ? Colors.red : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
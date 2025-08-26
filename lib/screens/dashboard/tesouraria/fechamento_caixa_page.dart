import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../repositories/tesouraria/fechamento_caixa_repository.dart';  // Repositório para carregamento de dados
import '../../../models/tesouraria/fechamento_caixa.dart'; // Modelo de Fechamento de Caixa
import '../../../api/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../../services/cad_lojas_service.dart';
import '../../home/menu_principal_page.dart';

class FechamentoCaixaPage extends StatefulWidget {
  const FechamentoCaixaPage({
    super.key,
  });

  @override
  _FechamentoCaixaPageState createState() => _FechamentoCaixaPageState();
}


// Filtro para diferenca (sobras/faltas/nenhuma/todas)
enum _FiltroDiferencaTipo { todas, sobras, faltas, nenhuma }
// Filtro para conferência (todos/conferidos/não conferidos)
enum _FiltroConferenciaTipo { todos, conferidos, naoConferidos }

class _FechamentoCaixaPageState extends State<FechamentoCaixaPage> {
  late final FechamentoCaixaRepository repository;
  DateTime _selectedDate = DateTime.now(); // Data selecionada
  int? _selectedCompany; // Alterado para int? para garantir que seja um número
  List<int> _empresasDisponiveis = []; // Lista de empresas disponíveis
  // Step 1: Add empresaNomes mapping
  Map<int, String> _empresaNomes = {};
  // Filtro de diferença (sobras/faltas/nenhuma/todas)
  _FiltroDiferencaTipo _filtroDiferenca = _FiltroDiferencaTipo.todas;
  // Filtro de conferência (todos/conferidos/não conferidos)
  _FiltroConferenciaTipo _filtroConferencia = _FiltroConferenciaTipo.todos;

  @override
  void initState() {
    super.initState();
    repository = FechamentoCaixaRepository(ApiClient(AuthService()));
    _loadEmpresas(); // Carrega as empresas quando a tela for inicializada
  }

  // Carrega as empresas e valida a empresa selecionada
  Future<void> _loadEmpresas() async {
    try {
      List<int> empresas = await repository.getEmpresasDisponiveis();

      // Step 2: Buscar nomes detalhados das empresas
      final service = CadLojasService(ApiClient(AuthService()));
      final empresasDetalhadas = await service.getEmpresasComNome();
      setState(() {
        for (var e in empresasDetalhadas) {
          _empresaNomes[e.id] = e.nome;
        }
        // Adiciona o nome da opção 0
        _empresaNomes[0] = 'Todas as Empresas'; // Adiciona a opção 0
        _empresasDisponiveis = [0, ...empresas]; // Insere o 0 no início da lista
        _selectedCompany = 0; // Seleciona "Todas as Empresas" por padrão
      });
      // Removido: seleção automática de empresa com caixas após carregamento.
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao carregar empresas: $e")));
    }
  }

  // Formata a data no padrão DD/MM/YYYY
  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString()
        .padLeft(2, '0')}/${date.year}";
  }

  // Exibe um date picker para escolher a data (liberando todas as datas)
  Future<void> _pickDate() async {
    final now = DateTime.now(); // Pega a data e hora local do dispositivo
    final truncatedNow = DateTime(now.year, now.month, now.day); // Remover hora, minuto, segundo e milissegundo

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      // Mantém a data inicial como a data de hoje
      firstDate: DateTime(1900),
      // Liberando a seleção para todas as datas anteriores
      lastDate: truncatedNow, // Usa a data truncada, sem a parte de horário
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D32),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }


  // Abre uma modal exibindo os detalhes do caixa clicado
  void _showDetalhes(FechamentoCaixa caixa) {
    final valorFormatado = "${NumberFormat.simpleCurrency(locale: 'pt_BR').format(caixa.valResultado)}";
    final bool exibirAlerta = caixa.valResultado < -100 ||
        caixa.valResultado > 100;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Caixa ${caixa.caixa} - Empresa ${caixa.idempresa}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Abertura ${caixa.abertura}"),
              Text("Usuário ${caixa.idusuario} - ${caixa.usuario}"),
              Text(
                caixa.flagconferido.trim().toUpperCase() == 'T'
                    ? "Conferido"
                    : "NÃO CONFERIDO",
                style: TextStyle(
                  color: caixa.flagconferido.trim().toUpperCase() == 'T'
                      ? Colors.green
                      : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              Text("Saldo do Caixa: $valorFormatado", style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
              if (exibirAlerta) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.amber),
                    const SizedBox(width: 5),
                    const Expanded(child: Text(
                        "Verifique se a tesouraria já foi encerrada.",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ],
            ],
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

  // Carrega e exibe os fechamentos de caixa filtrados
  Widget _buildList() {
    if (_selectedCompany == 0) {
      // Quando "Todas as Empresas" estiver selecionada
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: Future.wait(
          _empresasDisponiveis.where((e) => e != 0).map(
                (empresa) => repository.getFechamentoCaixaFiltrado(empresa, _selectedDate),
          ),
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Erro: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)));
          }

          double totalSobras = 0.0;
          double totalFaltas = 0.0;
          for (final map in snapshot.data ?? []) {
            final registros = map["registros"];
            for (final item in registros) {
              final fechamento = item as FechamentoCaixa;
              if (fechamento.valResultado > 0) {
                totalSobras += fechamento.valResultado;
              } else if (fechamento.valResultado < 0) {
                totalFaltas += fechamento.valResultado.abs();
              }
            }
          }

          final totalCards = [
            {
              "title": "Total Sobras",
              "value": NumberFormat.simpleCurrency(locale: 'pt_BR').format(totalSobras),
              "icon": Icons.attach_money,
              "onTap": null,
              "color": Colors.green,
            },
            {
              "title": "Total Faltas",
              "value": NumberFormat.simpleCurrency(locale: 'pt_BR').format(totalFaltas),
              "icon": Icons.money_off,
              "onTap": null,
              "color": Colors.red,
            },
          ];

          return ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              GridView.builder(
                itemCount: totalCards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.6,
                ),
                itemBuilder: (context, index) {
                  final card = totalCards[index];
                  return _DashboardCard(
                    title: card['title'] as String,
                    value: card['value'] as String,
                    icon: card['icon'] as IconData,
                    onTap: card['onTap'] as VoidCallback?,
                    color: card['color'] as Color?,
                  );
                },
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 8),
              ...List.generate(snapshot.data!.length, (index) {
                final empresaData = snapshot.data![index];
                final idEmpresa = _empresasDisponiveis.where((e) => e != 0).toList()[index];
                final nomeEmpresa = _empresaNomes[idEmpresa] ?? 'Empresa $idEmpresa';
                final registros = empresaData["registros"] as List<FechamentoCaixa>;
                registros.sort((a, b) => a.caixa.compareTo(b.caixa));
                // Filtrar registros conforme o filtro selecionado
                final registrosFiltrados = registros.where((item) {
                  // Filtro de conferência
                  final bool conferido = (item.flagconferido ?? '').trim().toUpperCase() == 'T';
                  if (_filtroConferencia == _FiltroConferenciaTipo.conferidos && !conferido) return false;
                  if (_filtroConferencia == _FiltroConferenciaTipo.naoConferidos && conferido) return false;
                  // Filtro de diferença
                  final bool isSobra = item.valResultado > 0;
                  final bool isFalta = item.valResultado < 0;
                  final bool isZerado = item.valResultado == 0;
                  if (_filtroDiferenca == _FiltroDiferencaTipo.sobras) return isSobra;
                  if (_filtroDiferenca == _FiltroDiferencaTipo.faltas) return isFalta;
                  if (_filtroDiferenca == _FiltroDiferencaTipo.nenhuma) return isZerado;
                  return true;
                }).toList();
                if (registrosFiltrados.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                      child: Text(
                        '$idEmpresa - $nomeEmpresa',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GridView.builder(
                      itemCount: registrosFiltrados.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.4,
                      ),
                      itemBuilder: (context, i) {
                        final item = registrosFiltrados[i];
                        final bool naoConferido = (item.flagconferido ?? '').trim().toUpperCase() != 'T';
                        final Color corTexto = naoConferido
                            ? Colors.red
                            : (item.valResultado >= 0 ? Colors.green : Colors.red);
                        return _DashboardCard(
                          title: 'Caixa ${item.caixa}\n${item.usuario}',
                          value: NumberFormat.simpleCurrency(locale: 'pt_BR').format(item.valResultado),
                          icon: Icons.point_of_sale,
                          onTap: () => _showDetalhes(item),
                          color: corTexto,
                        );
                      },
                    ),
                    const SizedBox(height: 16), // espaçamento entre empresas
                  ],
                );
              }),
            ],
          );
        },
      );
    }
    if (_selectedCompany == null ||
        !_empresasDisponiveis.contains(_selectedCompany)) {
      return const Center(child: Text(
          "Por favor, selecione uma empresa válida e a data.",
          style: TextStyle(color: Colors.white)));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: repository.getFechamentoCaixaFiltrado(
        _selectedCompany!,
        _selectedDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}',
              style: const TextStyle(color: Colors.red)));
        }

        Map<String, dynamic> resultado = snapshot.data ?? {};
        List<FechamentoCaixa> items = resultado["registros"];
        double totalSobras = 0.0;
        double totalFaltas = 0.0;
        for (var item in items) {
          if (item.valResultado > 0) {
            totalSobras += item.valResultado;
          } else if (item.valResultado < 0) {
            totalFaltas += item.valResultado.abs();
          }
        }
        // Sort items by caixa number before generating caixaCards
        items.sort((a, b) => a.caixa.compareTo(b.caixa));
        // Split cards: totalCards (first two), caixaCards (rest)
        final totalCards = [
          {
            "title": "Total Sobras",
            "value": NumberFormat.simpleCurrency(locale: 'pt_BR').format(totalSobras),
            "icon": Icons.attach_money,
            "onTap": null,
            "color": Colors.green,
          },
          {
            "title": "Total Faltas",
            "value": NumberFormat.simpleCurrency(locale: 'pt_BR').format(totalFaltas),
            "icon": Icons.money_off,
            "onTap": null,
            "color": Colors.red,
          },
        ];
        final caixaCards = <Map<String, dynamic>>[];
        for (var item in items) {
          // Filtro de conferência
          final bool conferido = (item.flagconferido ?? '').trim().toUpperCase() == 'T';
          if (_filtroConferencia == _FiltroConferenciaTipo.conferidos && !conferido) continue;
          if (_filtroConferencia == _FiltroConferenciaTipo.naoConferidos && conferido) continue;
          // Filtro de diferença
          final bool isSobra = item.valResultado > 0;
          final bool isFalta = item.valResultado < 0;
          final bool isZerado = item.valResultado == 0;
          if (_filtroDiferenca == _FiltroDiferencaTipo.sobras && !isSobra) continue;
          if (_filtroDiferenca == _FiltroDiferencaTipo.faltas && !isFalta) continue;
          if (_filtroDiferenca == _FiltroDiferencaTipo.nenhuma && !isZerado) continue;
          final bool naoConferido = (item.flagconferido ?? '').trim().toUpperCase() != 'T';
          final Color corTexto = naoConferido
              ? Colors.red
              : (item.valResultado >= 0 ? Colors.green : Colors.red);
          caixaCards.add({
            "title": "Caixa ${item.caixa}\n${item.usuario}",
            "value": NumberFormat.simpleCurrency(locale: 'pt_BR').format(item.valResultado),
            "icon": Icons.point_of_sale,
            "onTap": () => _showDetalhes(item),
            "color": corTexto,
          });
        }

        if (items.isEmpty) {
          return const Center(child: Text(
              'Nenhum dado encontrado', style: TextStyle(color: Colors.white)));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Grid of total cards
            GridView.builder(
              itemCount: totalCards.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.6,
              ),
              itemBuilder: (context, index) {
                final card = totalCards[index];
                return _DashboardCard(
                  title: card['title'] as String,
                  value: card['value'] as String,
                  icon: card['icon'] as IconData,
                  onTap: card['onTap'] as VoidCallback?,
                  color: card['color'] as Color?,
                );
              },
            ),
            // 2. Heading "Lista de Caixas"
            const Padding(
              padding: EdgeInsets.only(top: 12.0, bottom: 8.0),
              child: Text(
                'Lista de Caixas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            // 3. Grid of caixa cards
            GridView.builder(
              itemCount: caixaCards.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.6,
              ),
              itemBuilder: (context, index) {
                final card = caixaCards[index];
                return _DashboardCard(
                  title: card['title'] as String,
                  value: card['value'] as String,
                  icon: card['icon'] as IconData,
                  onTap: card['onTap'] as VoidCallback?,
                  color: card['color'] as Color?,
                );
              },
            ),
          ],
        );
      },
    );
  }

  // _cardData() removed



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MainDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        // actions removed: no status/cache icon
        actions: const [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filtros: Empresa e Data (vertical layout) - padrão DiferencaPedidoNotaDetalhesPage
            if (_empresasDisponiveis.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopupMenuButton<int>(
                    tooltip: 'Selecionar empresa',
                    itemBuilder: (context) => _empresasDisponiveis
                        .map((e) => PopupMenuItem(
                              value: e,
                              child: Text(e == 0
                                  ? '0 - Todas as Empresas'
                                  : '$e - ${_empresaNomes[e] ?? 'Empresa'}'),
                            ))
                        .toList(),
                    onSelected: (e) {
                      setState(() => _selectedCompany = e);
                    },
                    child: TextButton.icon(
                      icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                      label: Text(
                        _selectedCompany != null
                            ? (_selectedCompany == 0
                                ? '0 - Todas as Empresas'
                                : '${_selectedCompany!} - ${_empresaNomes[_selectedCompany!] ?? 'Empresa'}')
                            : 'Empresa',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87),
                      ),
                      onPressed: null,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_formatDate(_selectedDate)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12), // adicionar para espaçamento entre data e filtros
            Row(
              children: [
                InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (ctx) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.compare_arrows),
                                title: const Text('Somente sem diferença'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroDiferenca = _FiltroDiferencaTipo.nenhuma;
                                  });
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.arrow_upward),
                                title: const Text('Somente com sobras'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroDiferenca = _FiltroDiferencaTipo.sobras;
                                  });
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.arrow_downward),
                                title: const Text('Somente com faltas'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroDiferenca = _FiltroDiferencaTipo.faltas;
                                  });
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.select_all),
                                title: const Text('Todas'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroDiferenca = _FiltroDiferencaTipo.todas;
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _filtroDiferenca != _FiltroDiferencaTipo.todas ? const Color(0xFF2E7D32) : Colors.transparent,
                    ),
                    child: Icon(
                      Icons.compare_arrows,
                      size: 20,
                      color: _filtroDiferenca != _FiltroDiferencaTipo.todas ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (ctx) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.verified),
                                title: const Text('Apenas conferidos'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroConferencia = _FiltroConferenciaTipo.conferidos;
                                  });
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.warning),
                                title: const Text('Apenas não conferidos'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroConferencia = _FiltroConferenciaTipo.naoConferidos;
                                  });
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.select_all),
                                title: const Text('Todos'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _filtroConferencia = _FiltroConferenciaTipo.todos;
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _filtroConferencia != _FiltroConferenciaTipo.todos
                          ? const Color(0xFF2E7D32)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      Icons.verified_user,
                      size: 20,
                      color: _filtroConferencia != _FiltroConferenciaTipo.todos
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: SizedBox(),
                ),
              ],
            ),
            const SizedBox(height: 18), // manter espaçamento antes do título
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Resumo Fechamento de Caixas",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Remove the GridView.builder here and move it to _buildList's FutureBuilder
            // Instead, show the list (cards + items) in the FutureBuilder:
            _buildList(),
          ],
        ),
      ),
    );
  }
}

// Widget para exibir cada card de dashboard
// ignore: unused_element
class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: title.split('\n').asMap().entries.map((entry) {
                      final idx = entry.key;
                      final line = entry.value;
                      // Se for a linha do usuário (segunda linha), aplicar fontSize 11
                      return Text(
                        line,
                        style: TextStyle(
                          fontSize: idx == 1 ? 11 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color ?? Colors.black),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
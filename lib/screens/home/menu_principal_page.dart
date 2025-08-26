import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/auth_service.dart';

class MainDrawer extends StatefulWidget {
  const MainDrawer({super.key});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  static const _prefsKey = 'hidden_menu_labels';
  final Set<String> _hidden = {};
  late final ScrollController _drawerController;

  @override
  void initState() {
    super.initState();
    _drawerController = ScrollController();
    _loadHidden();
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  Future<void> _loadHidden() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hidden.addAll(prefs.getStringList(_prefsKey) ?? []);
    });
  }

  Future<void> _toggle(String label) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_hidden.contains(label)) {
        _hidden.remove(label);
      } else {
        _hidden.add(label);
      }
      prefs.setStringList(_prefsKey, _hidden.toList());
    });
  }

  bool _isHidden(String label) => _hidden.contains(label);

  void _showArchiveDialog() {
    final labels = <String>[
      // Agrupamentos // Módulos
      'Vendas',
        'Resumo de Vendas',
        'Produtos Sem Venda',
        'Top 10 em Vendas',
        'Fat. por Colaborador',
        'Comparativos',
          'Comparativo de Faturamento',
          'Comparativo por Empresa',
          'Comparativo por Empresa Diário',
      'Compras',
        'Dif. Pedido x Nota',
      'Financeiro',
        'Contas a Receber Vencidas',
        'Inadimplência',
        'Contas a Pagar Vencidas',
      'Estoque',
        'Resumo do Estoque',
        'Saldos Negativos',
        'Ruptura Percentual',
      'Metas',
        'Resumo de Metas',
      'Tesouraria',
        'Fechamento de Caixa',
    ];
    String filter = '';
    bool searchMode = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctxDialog, setStateDialog) {
          bool _sectionAllHidden(String section) {
            final int idx = labels.indexOf(section);
            if (idx < 0) return false;
            int end = labels.length;
            for (int i = idx + 1; i < labels.length; i++) {
              if (_isSectionTitle(labels[i])) { end = i; break; }
            }
            final children = labels
                .sublist(idx + 1, end)
                .where((l) => !_isSectionTitle(l))
                .toList();
            if (children.isEmpty) return false;
            return children.every((c) => _hidden.contains(c));
          }

          Future<void> _toggleSection(String section) async {
            final prefs = await SharedPreferences.getInstance();
            final int idx = labels.indexOf(section);
            if (idx < 0) return;
            int end = labels.length;
            for (int i = idx + 1; i < labels.length; i++) {
              if (_isSectionTitle(labels[i])) { end = i; break; }
            }
            final children = labels
                .sublist(idx + 1, end)
                .where((l) => !_isSectionTitle(l));

            final hideAll = !_sectionAllHidden(section) || !_hidden.contains(section);
            setStateDialog(() {
              // Toggle all children
              for (final c in children) {
                if (hideAll) {
                  _hidden.add(c);
                } else {
                  _hidden.remove(c);
                }
              }
              // Also toggle the section TITLE itself so o cabeçalho seja ocultado no Drawer
              if (hideAll) {
                _hidden.add(section);
              } else {
                _hidden.remove(section);
              }
              prefs.setStringList(_prefsKey, _hidden.toList());
            });
            if (mounted) setState(() {}); // Atualiza o Drawer por trás em tempo real
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(24),
              constraints: const BoxConstraints(
                maxWidth: 400,
                minHeight: 450,
                maxHeight: 600,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: searchMode
                            ? TextField(
                                autofocus: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'Pesquisar…',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (txt) {
                                  setStateDialog(() {
                                    filter = txt.toLowerCase();
                                  });
                                },
                              )
                            : const Text(
                                'Arquivar Indicadores',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                      IconButton(
                        icon: Icon(searchMode ? Icons.close : Icons.search),
                        tooltip: searchMode ? 'Fechar busca' : 'Pesquisar',
                        onPressed: () {
                          setStateDialog(() {
                            if (searchMode) {
                              // Fechou busca: limpa filtro e mostra título
                              filter = '';
                              searchMode = false;
                            } else {
                              // Abriu busca
                              searchMode = true;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  //const Divider(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: labels
                          .where((lbl) => lbl.toLowerCase().contains(filter))
                          .map(
                            (lbl) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isSectionTitle(lbl)) const Divider(),
                                CheckboxListTile(
                                  title: _isSectionTitle(lbl)
                                      ? Text(
                                          lbl,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        )
                                      : Text(lbl),
                                  value: _isSectionTitle(lbl)
                                      ? (_hidden.contains(lbl) || _sectionAllHidden(lbl))
                                      : _hidden.contains(lbl),
                                  onChanged: (_) async {
                                    if (_isSectionTitle(lbl)) {
                                      await _toggleSection(lbl);
                                    } else {
                                      await _toggle(lbl);
                                      setStateDialog(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctxDialog).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
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
      ),
    );
  }

  bool _isSectionTitle(String label) {
    const sections = [
      'Vendas',
      'Compras',
      'Financeiro',
      'Estoque',
      'Metas',
      'Tesouraria',
    ];
    return sections.contains(label);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF2E7D32), // cor do cabeçalho
      width: 250,
      child: ListView(
        controller: _drawerController,
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 100,
            child: DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(color: Color(0xFF2E7D32)),
              child: Row(
                children: [
                  const Text(
                    'Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (value) {
                      if (value == 'arquivar') _showArchiveDialog();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'arquivar',
                        child: Row(
                          children: const [
                            Icon(Icons.archive_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Arquivar Indicadores'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                if (!_isHidden('Início'))
                  _MenuItem(
                    icon: Icons.dashboard,
                    label: "Início",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/home');
                    },
                  ),
                const Divider(),
                if (!_isHidden('Vendas')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Vendas', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isHidden('Resumo de Vendas'))
                    _MenuItem(
                      icon: Icons.store,
                      label: "Resumo de Vendas",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/vendas');
                      },
                    ),
                  if (!_isHidden('Produtos Sem Venda'))
                    _MenuItem(
                      icon: Icons.store,
                      label: "Produtos Sem Venda",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/produtos_sem_venda');
                      },
                    ),
                  if (!_isHidden('Top 10 em Vendas'))
                    _MenuItem(
                      icon: Icons.bar_chart,
                      label: "Top 10 em Vendas",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/produtos_mais_vendidos');
                      },
                    ),
                  if (!_isHidden('Fat. por Colaborador'))
                    _MenuItem(
                      icon: Icons.people,
                      label: "Fat. por Colaborador",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/faturamento_colaborador');
                      },
                    ),
                  if (!_isHidden('Comparativos'))
                    ExpansionTile(
                      leading: const Icon(Icons.bar_chart, color: Colors.black87),
                      title: const Text("Comparativos"),
                      childrenPadding: const EdgeInsets.only(left: 16),
                      children: [
                        if (!_isHidden('Comparativo de Faturamento'))
                          _MenuItem(
                            icon: Icons.bar_chart,
                            label: "Comparativo de Faturamento",
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context,
                                  '/comparativo_faturamento_empresas_vendas');
                            },
                          ),
                        if (!_isHidden('Comparativo por Empresa'))
                          _MenuItem(
                            icon: Icons.business,
                            label: "Comparativo por Empresa",
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(
                                  context, '/comparativo_faturamento_por_empresa');
                            },
                          ),
                        if (!_isHidden('Comparativo por Empresa Diário'))
                          _MenuItem(
                            icon: Icons.calendar_view_day,
                            label: "Comparativo por Empresa Diário",
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context,
                                  '/comparativo_faturamento_por_empresa_diario');
                            },
                          ),
                      ],
                    ),
                  const Divider(),
                ],
                if (!_isHidden('Compras')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Compras', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isHidden('Dif. Pedido x Nota'))
                    _MenuItem(
                      icon: Icons.receipt_long,
                      label: "Dif. Pedido x Nota",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/diferenca_pedido_nota');
                      },
                    ),
                  const Divider(),
                ],
                if (!_isHidden('Financeiro')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Financeiro', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isHidden('Contas a Receber Vencidas'))
                    ListTile(
                      leading: const Icon(Icons.request_quote),
                      title: const Text('Contas a Receber Vencidas'),
                      onTap: () {
                        Navigator.of(context).pushNamed('/contas_receber');
                      },
                    ),
                  if (!_isHidden('Inadimplência'))
                    ListTile(
                      leading: const Icon(Icons.trending_down),
                      title: const Text('Inadimplência'),
                      onTap: () {
                        Navigator.of(context).pushNamed('/inadimplencia');
                      },
                    ),
                  if (!_isHidden('Contas a Pagar Vencidas'))
                    ListTile(
                      leading: const Icon(Icons.payment),
                      title: const Text('Contas a Pagar Vencidas'),
                      onTap: () {
                        Navigator.of(context).pushNamed('/contas_pagar');
                      },
                    ),
                  const Divider(),
                ],
                if (!_isHidden('Estoque')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Estoque', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isHidden('Resumo do Estoque'))
                    _MenuItem(
                      icon: Icons.inventory,
                      label: "Resumo do Estoque",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/estoque_page');
                      },
                    ),
                  if (!_isHidden('Saldos Negativos'))
                    _MenuItem(
                      icon: Icons.warning_amber,
                      label: "Saldos Negativos",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/produto_com_saldo_negativo');
                      },
                    ),
                  if (!_isHidden('Ruptura Percentual'))
                    _MenuItem(
                      icon: Icons.bar_chart,
                      label: "Ruptura Percentual",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/ruptura_percentual');
                      },
                    ),
                  const Divider(),
                ],
                if (!_isHidden('Metas')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Metas', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isHidden('Resumo de Metas'))
                    _MenuItem(
                      icon: Icons.flag,
                      label: "Resumo de Metas",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/metas');
                      },
                    ),
                  const Divider(),
                ],
                if (!_isHidden('Tesouraria')) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Tesouraria', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!_isHidden('Fechamento de Caixa'))
                    _MenuItem(
                      icon: Icons.point_of_sale,
                      label: "Fechamento de Caixa",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/fechamento_caixa');
                      },
                    ),
                  const Divider(),
                ],
                // const Divider(),
                // const _MenuItem(icon: Icons.settings, label: "Suporte"),
                _MenuItem(
                  icon: Icons.logout,
                  label: "Deslogar",
                  onTap: () async {
                    final authService = AuthService();
                    await authService.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  },
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(label),
      onTap: onTap ?? () => Navigator.pop(context),
    );
  }
}
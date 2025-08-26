import 'dart:async';
import 'package:flutter/material.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/services/caches/produto_com_saldo_negativo_cache.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import '../../../models/estoque/produto_com_saldo_negativo_model.dart';
import '../../../repositories/estoque/produto_com_saldo_negativo_repository.dart';
import '../../home/menu_principal_page.dart';

class ProdutoComSaldoNegativoPage extends StatefulWidget {
  const ProdutoComSaldoNegativoPage({Key? key}) : super(key: key);

  @override
  State<ProdutoComSaldoNegativoPage> createState() =>
      _ProdutoComSaldoNegativoPageState();
}

class _ProdutoComSaldoNegativoPageState
    extends State<ProdutoComSaldoNegativoPage> with WidgetsBindingObserver {
  // Variável para registrar o início da execução da consulta
  late DateTime _inicioExecucao;
  // Filtro para produtos inativos: "T" = inativos, "F" = ativos
  String _filtroInativo = "F";
  DateTime? _ultimoCarregamento;
  // Lista de empresas carregadas do serviço
  List<Empresa> _empresas = [];
  // Empresa atualmente selecionada
  Empresa? _empresaSelecionada;
  // Data de corte para a consulta
  DateTime _dataSelecionada = DateTime.now();
  // Flag que indica se produtos inativos devem ser incluídos (“T” ou “F”)
  String _flagInativo = 'F';

  final _repository = ProdutoComSaldoNegativoRepository(ApiClient(AuthService()));
  final _cache = ProdutoComSaldoNegativoCache.instance;
  late final TempoExecucaoRepository _tempoRepo;

  bool _isLoading = false;
  bool _groupSecao = true;
  bool _groupDivisao = false;

  double? _tempoExecucao;
  double? _tempoMedioEstimado;
  double _cronometro = 0.0;
  Timer? _cronometroTimer;
  static DateTime? _globalConsultaInicio;

  /// Lista completa dos produtos retornados pela API
  List<ProdutoComSaldoNegativo> _todos = [];
  /// Lista filtrada ou apresentada (por exemplo, usada para reagrupamento)
  List<ProdutoComSaldoNegativo> _lista = [];
  /// Lista de resumos agrupados (quando o usuário escolher agrupar)
  List<Map<String, dynamic>> _groupResumo = [];

  // =====================  CACHE COMPARTILHADO (30 min) =====================
  // *** NOVO: variáveis estáticas para compartilhar cache entre instâncias da tela
  static Future<void>? _globalFuture;
  static bool _globalFetching = false;

  static List<ProdutoComSaldoNegativo>? _cachedLista;
  static DateTime? _listaTimestamp;
  static int? _listaEmpresa;
  static String? _listaFlagInativo;
  static String? _listaData; // dd/MM/yyyy
  static const int _listaTtlMin = 30; // minutos

  // *** NOVO: controle local
  bool _hasFetched = false;

  // *** NOVO: cronômetro visual igual ao ProdutosSemVendaPage
  void _startCronometro() {
    if (_globalConsultaInicio == null) return;
    _cronometroTimer?.cancel();
    _cronometroTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _globalConsultaInicio == null) return;
      final elapsedMs = DateTime.now().difference(_globalConsultaInicio!).inMilliseconds;
      setState(() => _cronometro = elapsedMs / 1000);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tempoRepo = TempoExecucaoRepository();
    _carregarEmpresas();
    // *** REMOVIDO: checagem de cache inicial duplicada – agora é feita dentro de _carregarDados()
  }
  // Adicionado método _buscarDados conforme solicitado
  Future<void> _buscarDados() async {
    await _carregarDados();
    _ultimoCarregamento = DateTime.now();
    // Salva os dados em cache após buscar da API
    final produtoComSaldoNegativoCache = ProdutoComSaldoNegativoCache.instance;
    final idEmpresa = _empresaSelecionada?.id ?? 0;
    final dataFormatada = DateTime.parse(_dataSelecionada.toIso8601String());
    produtoComSaldoNegativoCache.setProdutos(
      idEmpresa,
      dataFormatada,
      _filtroInativo,
      _todos,
    );
  }

  @override
  void dispose() {
    _cronometroTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Carrega as empresas (buscando do cache ou do serviço) e, após isso,
  /// inicializa o tempo de execução e carrega os dados de produtos.
  Future<void> _carregarEmpresas() async {
    List<Empresa> empresas;
    // Verifica se as empresas estão em cache e se o cache ainda é válido
    final cacheOk = _cache.cachedEmpresas != null &&
        _cache.empresasTimestamp != null &&
        DateTime.now()
            .difference(_cache.empresasTimestamp!)
            .inMinutes <
            _cache.empresasTtlMin;

    if (cacheOk) {
      empresas = List<Empresa>.from(_cache.cachedEmpresas!);
    } else {
      final service = CadLojasService(ApiClient(AuthService()));
      empresas = await service.getEmpresasComNome();
      _cache.setEmpresas(empresas);
    }

    setState(() {
      _empresas = empresas;
      // todas as empresas esta bloqueado para uso por enquanto, precisa ativar a ajustar no futuro
      // _empresas.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
      _empresaSelecionada = _cache.lastEmpresaSelecionada ??
          (_empresas.length > 1 ? _empresas[1] : _empresas.first);
      _cache.lastEmpresaSelecionada = _empresaSelecionada;
    });

    await _inicializarTempoExecucao();
    await _carregarDados();
  }

  /// Busca o tempo de execução mais recente e o tempo médio para a chave
  /// composta por empresa e data selecionada.
  Future<void> _inicializarTempoExecucao() async {
    if (_empresaSelecionada == null) return;
    final chave =
        '${_empresaSelecionada!.id}_${_formatDate(_dataSelecionada)}';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoExecucao = ultimo;
        _tempoMedioEstimado = media;
      });
    }
  }

  /// Formata a data no padrão dd/MM/yyyy sem precisar de pacote externo.
  String _formatDate(DateTime date) {
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    final ano = date.year.toString().padLeft(4, '0');
    return '$dia/$mes/$ano';
  }

  /// Permite ao usuário selecionar uma nova data. Atualiza a data, reinicializa
  /// o tempo de execução e recarrega os dados.
  Future<void> _selecionarData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _dataSelecionada) {
      setState(() {
        _dataSelecionada = picked;
      });
      await _inicializarTempoExecucao();
      await _carregarDados();
    }
  }

  /// Calcula o resumo de quantidades agrupadas por seção ou divisão.
  List<Map<String, dynamic>> _calcularResumo(List<ProdutoComSaldoNegativo> dados) {
    final Map<String, int> contagem = {};
    for (final item in dados) {
      String chave;
      if (_groupSecao) {
        chave = item.descrsecao ?? 'Sem Seção';
      } else {
        chave = item.descrdivisao ?? 'Sem Divisão';
      }
      contagem.update(chave, (value) => value + 1, ifAbsent: () => 1);
    }

    return contagem.entries
        .map((e) => {'grupo': e.key, 'total': e.value})
        .toList();
  }

  /// Carrega os dados da API OU do cache com lógica de forçar atualização.
  Future<void> _carregarDados({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
    });
    // Inicia o cronômetro visual
    if (_globalConsultaInicio == null) {
      _cronometro = 0.0;
      _globalConsultaInicio = DateTime.now();
    }
    _startCronometro();

    print('🔍 Buscando com flagInativo = $_filtroInativo');

    // Inicia a contagem do tempo de execução da consulta
    _inicioExecucao = DateTime.now();

    List<ProdutoComSaldoNegativo>? produtos;

    if (_empresaSelecionada == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (forceRefresh) {
      produtos = await ProdutoComSaldoNegativoRepository(ApiClient(AuthService())).getProdutoComSaldoNegativo(
        empresas: [_empresaSelecionada!.id],
        dataFim: _formatDate(_dataSelecionada),
        flagInativo: _filtroInativo,
      );
      ProdutoComSaldoNegativoCache.instance.setProdutos(
        _empresaSelecionada!.id,
        _dataSelecionada,
        _filtroInativo,
        produtos,
      );
    } else {
      produtos = ProdutoComSaldoNegativoCache.instance.getProdutos(
        _empresaSelecionada!.id,
        _dataSelecionada,
        _filtroInativo,
      );
      if (produtos == null) {
        produtos = await ProdutoComSaldoNegativoRepository(ApiClient(AuthService())).getProdutoComSaldoNegativo(
          empresas: [_empresaSelecionada!.id],
          dataFim: _formatDate(_dataSelecionada),
          flagInativo: _filtroInativo,
        );
        ProdutoComSaldoNegativoCache.instance.setProdutos(
          _empresaSelecionada!.id,
          _dataSelecionada,
          _filtroInativo,
          produtos,
        );
      } else {
        setState(() {
          _todos = produtos!;
          _aplicarAgrupamentoLocal();
          _isLoading = false;
          _hasFetched = true;
          _tempoExecucao = null;
          _cronometro = 0;
        });
        _cronometroTimer?.cancel();
        _globalConsultaInicio = null;
        return;
      }
    }

    final tempoFinal = DateTime.now();
    final duracao = tempoFinal.difference(_inicioExecucao);
    await _tempoRepo.salvarTempo(
      '${_empresaSelecionada!.id}_${_formatDate(_dataSelecionada)}',
      duracao.inMilliseconds,
    );

    final tempoSegundos = duracao.inMilliseconds.toDouble() / 1000;
    setState(() {
      _todos = produtos ?? [];
      _aplicarAgrupamentoLocal();
      _isLoading = false;
      _hasFetched = true;
      _cronometro = tempoSegundos;
      _tempoExecucao = duracao.inMilliseconds.toDouble();
    });
    // Atualiza o tempo médio estimado após salvar o tempo atual
    final media = await _tempoRepo.buscarTempoMedio(
      '${_empresaSelecionada!.id}_${_formatDate(_dataSelecionada)}',
    );
    setState(() {
      _tempoMedioEstimado = media;
    });
    _cronometroTimer?.cancel();
    _globalConsultaInicio = null;
  }

  /// Atualiza os dados agrupados localmente sem nova chamada à API.
  void _recarregarDados() {
    setState(() {
      _aplicarAgrupamentoLocal();
    });
    _atualizarCards();
  }

  /// Aplica o agrupamento local, mantendo todos os dados para visualização e preenchendo _groupResumo.
  void _aplicarAgrupamentoLocal() {
    _lista = List.from(_todos); // mantém todos para visualização
    if (_groupSecao || _groupDivisao) {
      _groupResumo = _calcularResumo(_todos);
    } else {
      _groupResumo = [];
    }
  }

  /// Atualiza os cards de agrupamento conforme o filtro local.
  void _atualizarCards() {
    setState(() {
      if (_groupSecao || _groupDivisao) {
        _groupResumo = _calcularResumo(_todos);
      } else {
        _groupResumo = [];
      }
    });
  }

  /// Constrói a lista de agrupamentos ou de produtos conforme as opções
  /// selecionadas. Nova versão com cards e detalhamento modal.
  Widget _buildListView() {
    final entries = _groupResumo;
    if (_groupSecao || _groupDivisao) {
      return GridView.builder(
        itemCount: entries.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.0,
        ),
        itemBuilder: (context, idx) {
          final entry = entries[idx];
          final key = entry['grupo'] ?? '';
          final total = entry['total'].toString();
          return InkWell(
            onTap: () {
              final filtered = _lista.where((item) {
                return (_groupSecao && item.descrsecao == key) ||
                       (_groupDivisao && item.descrdivisao == key);
              }).toList();

              _mostrarDetalhesGrupo(key, filtered);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 100),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.list, size: 18, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 4),
                      Text(
                        '$total itens',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      return ListView.builder(
        itemCount: _lista.length,
        itemBuilder: (context, index) {
          final p = _lista[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.idsubproduto} - ${p.descricaoproduto}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.inventory, size: 20, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text('Estoque: ${p.qtdatualestoque.toStringAsFixed(0)}'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.attach_money, size: 20, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('Preço de venda: R\$ ${p.saldovarejo.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.shopping_cart, size: 20, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Text('Custo última compra: R\$ ${p.customedio.toStringAsFixed(2)}'),
                  ],
                ),
                const Divider(height: 16),
              ],
            ),
          );
        },
      );
    }
  }

  void _mostrarDetalhesGrupo(String titulo, List<ProdutoComSaldoNegativo> itens) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  '$titulo (${itens.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: itens.length,
                    itemBuilder: (context, idx) {
                      final p = itens[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p.idsubproduto} - ${p.descricaoproduto.trim()}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.inventory, size: 20, color: Colors.orange),
                                const SizedBox(width: 6),
                                Text('Estoque: ${p.qtdatualestoque.toStringAsFixed(0)}'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.attach_money, size: 20, color: Colors.blue),
                                const SizedBox(width: 6),
                                Text('Preço de venda: R\$ ${p.saldovarejo.toStringAsFixed(2)}'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.shopping_cart, size: 20, color: Colors.redAccent),
                                const SizedBox(width: 6),
                                Text('Custo última compra: R\$ ${p.customedio.toStringAsFixed(2)}'),
                              ],
                            ),
                            const Divider(height: 16),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Fechar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: const [],
      ),
      drawer: const MainDrawer(),
      body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
            // Filtros estilizados (empresa, data, inativos, agrupamento)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Empresa
                  if (_empresas.isNotEmpty)
                    IgnorePointer(
                      ignoring: _isLoading,
                      child: Opacity(
                        opacity: _isLoading ? 0.5 : 1.0,
                        child: PopupMenuButton<Empresa>(
                          itemBuilder: (_) => _empresas.map((e) =>
                              PopupMenuItem(value: e, child: Text(e.toString()))
                          ).toList(),
                          onSelected: (e) async {
                            if (_isLoading) return;
                            setState(() => _empresaSelecionada = e);
                            await _inicializarTempoExecucao();
                            _carregarDados();
                          },
                          child: TextButton.icon(
                            icon: const Icon(Icons.business, size: 18, color: Colors.black87),
                            label: Text(
                              _empresaSelecionada?.nome ?? 'Empresa',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: null,
                          ),
                        ),
                      ),
                    ),

                  // Data
                  IgnorePointer(
                    ignoring: _isLoading,
                    child: Opacity(
                      opacity: _isLoading ? 0.5 : 1.0,
                      child: TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18, color: Colors.black87),
                        label: Text(
                          _formatDate(_dataSelecionada),
                          style: const TextStyle(color: Colors.black87),
                        ),
                        onPressed: _selecionarData,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Espaço entre data e botões de grupo
            const SizedBox(height: 5),
            // Nova Row para Divisão, Seção e filtro de estoque, logo abaixo da data
            Row(
              children: [
                // Divisão
                FilterChip(
                  label: const Text('Divisão'),
                  selected: _groupDivisao,
                  onSelected: (v) {
                    if (_isLoading) return;
                    setState(() {
                      if (v) {
                        _groupDivisao = true;
                        _groupSecao = false;
                      } else {
                        _groupDivisao = false;
                        _groupSecao = true;
                      }
                    });
                    _recarregarDados();
                  },
                  backgroundColor: Colors.grey.shade200,
                  selectedColor: Colors.grey.shade200,
                  checkmarkColor: Colors.black87,
                  labelStyle: const TextStyle(color: Colors.black87),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: _groupDivisao ? Colors.black87 : Colors.transparent,
                      width: 0,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // Seção
                FilterChip(
                  label: const Text('Seção'),
                  selected: _groupSecao,
                  onSelected: (v) {
                    if (_isLoading) return;
                    setState(() {
                      if (v) {
                        _groupSecao = true;
                        _groupDivisao = false;
                      } else {
                        _groupSecao = false;
                        _groupDivisao = true;
                      }
                    });
                    _recarregarDados();
                  },
                  backgroundColor: Colors.grey.shade200,
                  selectedColor: Colors.grey.shade200,
                  checkmarkColor: Colors.black87,
                  labelStyle: const TextStyle(color: Colors.black87),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: _groupSecao ? Colors.black87 : Colors.transparent,
                      width: 0,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // Botão de filtro inativo/ativo (ao lado do botão Seção)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 0),
                  child: IconButton(
                    onPressed: () {
                      final novoValor = _filtroInativo == "T" ? "F" : "T";

                      setState(() {
                        _filtroInativo = novoValor;
                      });

                      final textoSnackBar = novoValor == "T"
                          ? '🔄 Exibindo produtos INATIVOS.'
                          : '🔄 Exibindo produtos ATIVOS.';

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(textoSnackBar),
                          duration: const Duration(seconds: 2),
                        ),
                      );

                      _carregarDados(forceRefresh: true);
                    },
                    tooltip: _filtroInativo == "T"
                        ? "Somente produtos inativos"
                        : "Somente produtos ativos",
                    icon: Icon(
                      _filtroInativo == "T" ? Icons.block : Icons.check_circle,
                      color: _filtroInativo == "T" ? Colors.red[700] : Colors.green[700],
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Saldos Negativos',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: '  ${_cronometro.toStringAsFixed(1)}s',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    TextSpan(
                      text: ' (~${(_tempoMedioEstimado ?? 0).toStringAsFixed(1)}s)',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Área principal: lista ou indicador de carregamento
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _lista.isEmpty && _groupResumo.isEmpty
                    ? const Center(
                        child: Text('Nenhum produto encontrado.'),
                      )
                    : _buildListView(),
            ),
          ],
        ),
      ),
    );
  }
}
  // O agrupamento real deve ser feito apenas neste método, usando groupBy conforme _groupSecao/_groupDivisao.
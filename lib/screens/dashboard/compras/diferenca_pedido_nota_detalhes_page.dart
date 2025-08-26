import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:analyzepro/api/api_client.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';
import 'package:analyzepro/services/auth_service.dart';
import 'package:analyzepro/services/cad_lojas_service.dart';
import 'package:analyzepro/repositories/cronometro/tempo_execucao_repository.dart';
import '../../../models/compras/diferenca_pedido_nota_model_detalhes.dart';
import '../../../repositories/compras/diferenca_pedido_nota_repository_detalhes.dart';
// Enum para definir o tipo de divergência de quantidade (escopo privado do arquivo)
enum _QtdFiltroTipo { qualquerDif, notaMaior, pedidoMaior }
/// Página: Diferença Pedido × Nota (Resumo)
///
/// Estrutura replica os “recursos” da tela de Contas a Receber:
///  • Escolha de empresa via `PopupMenuButton`
///  • Seletor de intervalo de datas
///  • Grade de cards de resumo com carregamento individual
///  • Lista (tap‑to‑expand) dos fornecedores divergentes
///  • Cronômetro visual simples enquanto consulta a API
///
/// _Obs.:_  Não há cache nem cronômetro médio → mantemos só o cronômetro
/// instantâneo para não inflar o código.
class DiferencaPedidoNotaDetalhesPage extends StatefulWidget {
  final int idEmpresa;
  final int idCliFor;
  final String nomeFornecedor;
  final double valorMinDif;
  final DateTimeRange intervalo;

  const DiferencaPedidoNotaDetalhesPage({
    super.key,
    required this.idEmpresa,
    required this.idCliFor,
    required this.nomeFornecedor,
    required this.valorMinDif,
    required this.intervalo,
  });

  @override
  State<DiferencaPedidoNotaDetalhesPage> createState() => _DiferencaPedidoNotaDetalhesPageState();
}

class _DiferencaPedidoNotaDetalhesPageState extends State<DiferencaPedidoNotaDetalhesPage> with WidgetsBindingObserver {
  // =============================================
  // Serviços / Repositórios
  // =============================================
  late final AuthService _auth;
  late final ApiClient _api;
  late final DiferencaPedidoNotaDetalhesRepository _repo;

  // --- Cronômetro médio/histórico ---
  late final TempoExecucaoRepository _tempoRepo;
  double? _tempoMedioEstimado;


  // =============================================
  // Filtros
  // =============================================
  List<Empresa> _empresas = [];
  Empresa? _empresaSelecionada;
  DateTimeRange? _intervalo;
  double _valorMinDif = 5.0;   // default, will be overwritten in initState

  // =============================================
  // Estado de UI
  // =============================================
  bool _listaLoading = false;
  bool _disposed = false;
  // ===== INÍCIO: flag para filtrar itens com qtd divergente =====
  bool _filtrarQtdDif = false;
  // -- Tipo de filtro aplicado sobre quantidades --
  _QtdFiltroTipo _tipoFiltroQtd = _QtdFiltroTipo.qualquerDif;
  // ===== FIM: flag para filtrar itens com qtd divergente =====

  // Cronômetro simples
  Timer? _timer;
  double _cronometro = 0;

  // Dados
  List<DiferencaPedidoNotaDetalhesModel> _itens = [];

  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = AuthService();
    _api = ApiClient(_auth);
    _repo = DiferencaPedidoNotaDetalhesRepository(_api);
    _tempoRepo = TempoExecucaoRepository();
    _valorMinDif = widget.valorMinDif;
    _intervalo   = widget.intervalo;
    _carregarEmpresas();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // =============================================
  // Carregar empresas (mesma lógica simplificada)
  // =============================================
  Future<void> _carregarEmpresas() async {
    final service = CadLojasService(_api);
    final emps = await service.getEmpresasComNome();
    if (emps.isNotEmpty && emps.first.id != 0) {
      emps.insert(0, Empresa(id: 0, nome: 'Todas as Empresas'));
    }
    final hoje = DateTime.now();
    final inicio = DateTime(hoje.year, hoje.month, hoje.day);
    final fim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);

    if (mounted) {
      setState(() {
        _empresas = emps;
        _empresaSelecionada = emps.firstWhere(
          (e) => e.id == widget.idEmpresa,
          orElse: () => emps.isNotEmpty
              ? emps.first
              : Empresa(id: widget.idEmpresa, nome: 'Empresa ${widget.idEmpresa}'),
        );
        _intervalo = _intervalo ?? DateTimeRange(start: inicio, end: fim);
      });
    }

    await _inicializarTempoExecucao();
    _carregarDados();
  }

  Future<void> _inicializarTempoExecucao() async {
    if (_empresaSelecionada == null || _intervalo == null) return;
    final dias = _intervalo!.end.difference(_intervalo!.start).inDays;
    final chave = '${_empresaSelecionada!.id}|$dias|dif_ped_nota';
    final ultimo = await _tempoRepo.buscarUltimoTempo(chave);
    final media = await _tempoRepo.buscarTempoMedio(chave);
    if (mounted) {
      setState(() {
        _tempoMedioEstimado = media;
      });
    }
  }

  // =============================================
  // Carregar dados principais
  // =============================================
  Future<void> _carregarDados() async {
    if (_empresaSelecionada == null || _intervalo == null) return;

    final Stopwatch _sw = Stopwatch()..start();

    // ---- Ativa loaders & cronômetro ----
    _listaLoading = true;
    _cronometro = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tickCron());
    if (mounted) setState(() {});

    try {
      // Consulta detalhada de itens divergentes
      final List<Empresa> alvo = _empresaSelecionada!.id == 0
          ? _empresas.where((e) => e.id != 0).toList()
          : [_empresaSelecionada!];
      final List<DiferencaPedidoNotaDetalhesModel> agregados = [];
      for (final emp in alvo) {
        final lista = await _repo.fetchDetalhes(
          idEmpresa: emp.id,
          idClifor: widget.idCliFor,
          valorMinDif: _valorMinDif,
          dataInicial: _intervalo!.start,
          dataFinal: _intervalo!.end,
        );
        agregados.addAll(lista);
      }
      if (mounted) {
        setState(() {
          _itens = List<DiferencaPedidoNotaDetalhesModel>.from(agregados)
            ..sort((a, b) => b.dif.compareTo(a.dif));
        });
      }
    } finally {
      // ---- Desliga loaders & cronômetro ----
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _listaLoading = false;
        });
      }
      _sw.stop();
      final dias = _intervalo!.end.difference(_intervalo!.start).inDays;
      final chave = '${_empresaSelecionada!.id}|$dias|dif_ped_nota';
      final tempoReal = _sw.elapsedMilliseconds / 1000;
      try {
        await _tempoRepo.salvarTempo(chave, _sw.elapsedMilliseconds);
      } catch (_) {}
      // Removido o setState para _tempoExecucao, pois o campo foi removido.
      final media = await _tempoRepo.buscarTempoMedio(chave);
      if (mounted) {
        setState(() {
          _tempoMedioEstimado = media;
        });
      }
    }
  }

  void _tickCron() {
    if (_disposed) return;
    setState(() => _cronometro += 0.1);
  }

  // =============================================
  // UI helpers
  // =============================================
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _intervalo,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D32),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Color(0xFF2E7D32)),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _intervalo = picked);
      await _inicializarTempoExecucao();
      _carregarDados();
    }
  }

  String _intervaloFmt() {
    if (_intervalo == null) return 'Selecione o intervalo';
    return '${_fmt.format(_intervalo!.start)} - ${_fmt.format(_intervalo!.end)}';
  }

  // =============================================
  // Build
  // =============================================
  @override
  Widget build(BuildContext context) {
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
            // ===================================================
            // Filtros (Empresa, Data, Valor mínimo)
            // ===================================================
            if (_empresas.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopupMenuButton<Empresa>(
                    tooltip: 'Selecionar empresa',
                    itemBuilder: (ctx) => _empresas
                        .map((e) => PopupMenuItem(
                              value: e,
                              child: Text(e.toString()),
                            ))
                        .toList(),
                    onSelected: (e) async {
                      setState(() => _empresaSelecionada = e);
                      await _inicializarTempoExecucao();
                      _carregarDados();
                    },
                    child: TextButton.icon(
                      icon:
                          const Icon(Icons.business, size: 18, color: Colors.black87),
                      label: Text(
                        _empresaSelecionada?.toString() ?? 'Empresa',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87),
                      ),
                      onPressed: null,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_intervaloFmt(),
                        overflow: TextOverflow.ellipsis),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ===== INÍCIO: Ícone de filtro qtd divergente =====
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Dif. Pedido x Nota',
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
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() => _filtrarQtdDif = !_filtrarQtdDif);
                        },
                        onLongPress: () {
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
                                      leading: const Icon(Icons.arrow_upward),
                                      title: const Text('Chegou mais do que pedimos'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        setState(() {
                                          _filtrarQtdDif = true;
                                          _tipoFiltroQtd = _QtdFiltroTipo.notaMaior;
                                        });
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.arrow_downward),
                                      title: const Text('Chegou menos do que pedimos'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        setState(() {
                                          _filtrarQtdDif = true;
                                          _tipoFiltroQtd = _QtdFiltroTipo.pedidoMaior;
                                        });
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.swap_horiz),
                                      title: const Text('Qualquer divergência'),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        setState(() {
                                          _filtrarQtdDif = true;
                                          _tipoFiltroQtd = _QtdFiltroTipo.qualquerDif;
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
                            color: _filtrarQtdDif ? const Color(0xFF2E7D32) : Colors.transparent,
                          ),
                          child: Icon(
                            Icons.compare_arrows,
                            size: 20,
                            color: _filtrarQtdDif ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  )
                  // ===== FIM: Ícone de filtro qtd divergente =====
                ],
              ),

            // (Itens list directly follows header/filtros)
            // ===================================================
            // Lista de Itens
            // ===================================================
            if (_listaLoading)
              const Center(child: CircularProgressIndicator())
            else
              // ===== INÍCIO: aplicação do filtro de quantidade divergente =====
              (() {
                final itensParaExibir = !_filtrarQtdDif
                    ? _itens
                    : _itens.where((i) {
                        switch (_tipoFiltroQtd) {
                          case _QtdFiltroTipo.notaMaior:
                            return i.qtdNota > i.qtdSolicitada;
                          case _QtdFiltroTipo.pedidoMaior:
                            return i.qtdNota < i.qtdSolicitada;
                          case _QtdFiltroTipo.qualquerDif:
                            return i.qtdNota != i.qtdSolicitada;
                        }
                      }).toList();
                return Column(
                  children: itensParaExibir
                      .map((item) => _ItemCard(item: item))
                      .toList(),
                );
              })(),
              // ===== FIM: aplicação do filtro de quantidade divergente =====
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// UI COMPONENTES
// ===================================================================

class _ItemCard extends StatelessWidget {
  final DiferencaPedidoNotaDetalhesModel item;
  const _ItemCard({required this.item});

  // Helper method for info row
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return InkWell(
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
                      item.descrResProduto.trim(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(Icons.numbers, 'Nota', item.numNota.toString()),
                    _buildInfoRow(Icons.receipt_long, 'Pedido', item.idPedido.toString()),
                    _buildInfoRow(Icons.calendar_today, 'Dt mov.', DateFormat('dd/MM/yyyy').format(DateTime.parse(item.dtMovimento))),
                    _buildInfoRow(Icons.inventory, 'Qtd nota', item.qtdNota.toStringAsFixed(3)),
                    _buildInfoRow(Icons.playlist_add_check, 'Qtd pedida', item.qtdSolicitada.toStringAsFixed(3)),
                    _buildInfoRow(Icons.shopping_cart_outlined, 'Total pedido', currency.format(item.pedTotal)),
                    _buildInfoRow(Icons.receipt, 'Total nota', currency.format(item.valTotBruto)),
                    _buildInfoRow(Icons.paid, 'Diferença', currency.format(item.dif)),
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
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(24),
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
            // ---------- Nome do produto ----------
            Text(
              item.descrResProduto,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // ---------- Diferença (R$) ----------
            Row(
              children: [
                const Icon(Icons.paid, size: 20, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.dif),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ---------- Quantidades ----------
            Row(
              children: [
                const Icon(Icons.list_alt, size: 20, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Qtd nota: ${item.qtdNota}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: item.qtdNota < item.qtdSolicitada
                                ? Colors.red
                                : item.qtdNota > item.qtdSolicitada
                                    ? Colors.amber[800]
                                    : Colors.black,
                          ),
                        ),
                        const TextSpan(
                          text: '  •  ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: 'Ped.: ${item.qtdSolicitada}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
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

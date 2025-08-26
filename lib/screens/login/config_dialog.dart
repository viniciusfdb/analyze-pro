import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/config_service.dart';
import 'dart:convert';

class ConfigDialog extends StatefulWidget {
  final Function() onConfigUpdated;

  const ConfigDialog({
    super.key,
    required this.onConfigUpdated,
  });

  @override
  _ConfigDialogState createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<ConfigDialog> {
  final GlobalKey _fieldKey = GlobalKey();
  bool _temConfiguracaoSalva = false;
  bool _configAlterada = false;
  late TextEditingController _baseUrlController;
  late TextEditingController _portController;
  bool _isSslEnabled = true;
  bool _isLoading = true;
  List<Map<String, dynamic>> _conexoes = [];

  Future<void> _salvarNovaConexao(String host, String porta, bool usarSsl) async {
    final prefs = await SharedPreferences.getInstance();
    final conexoes = prefs.getStringList('conexoes_salvas') ?? [];

    final novaConexao = {
      'host': host,
      'porta': porta,
      'usarSsl': usarSsl.toString(),
    };

    final novaConexaoJson = jsonEncode(novaConexao);

    final jaExiste = conexoes.any((c) {
      final Map<String, dynamic> conn = jsonDecode(c);
      return conn['host'] == host && conn['porta'] == porta;
    });

    if (!jaExiste) {
      conexoes.add(novaConexaoJson);
      await prefs.setStringList('conexoes_salvas', conexoes);
    }
  }

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _portController = TextEditingController();
    _loadConfig();
    _carregarConexoes();
  }

  Future<void> _carregarConexoes() async {
    final prefs = await SharedPreferences.getInstance();
    final conexoesRaw = prefs.getStringList('conexoes_salvas') ?? [];
    final listaMapeada = conexoesRaw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    final unicos = <String, Map<String, dynamic>>{};
    for (var con in listaMapeada) {
      final chave = '${con['host']}:${con['porta']}';
      final nomeCurto = con['host'].toString().split('.').first;
      unicos[chave] = {
        ...con,
        'nomeCurto': nomeCurto,
      };
    }
    setState(() {
      _conexoes = unicos.values.toList();
    });
  }

  Future<void> _loadConfig() async {
    String? baseUrl = await ConfigService.getBaseUrl();
    _temConfiguracaoSalva = baseUrl != null;

    String host = '';
    String port = '4665';
    bool isSslEnabled = true;

    if (baseUrl != null) {
      isSslEnabled = baseUrl.startsWith('https://');
      String cleanedUrl = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
      List<String> hostPortParts = cleanedUrl.split('/').first.split(':');
      host = hostPortParts[0];
      if (hostPortParts.length > 1) {
        port = hostPortParts[1];
      } else {
        port = isSslEnabled ? '443' : '4665';
      }
    }

    await _carregarConexoes(); // <- adicionado aqui

    setState(() {
      _isSslEnabled = isSslEnabled;
      _baseUrlController.text = host;
      _portController.text = port;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final newBaseUrl = _baseUrlController.text.trim();
    final port = _portController.text.trim();

    // Validação básica
    if (newBaseUrl.isEmpty || port.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("URL e porta são obrigatórios")),
      );
      return;
    }

    final urlRegExp = RegExp(r'^[a-zA-Z0-9\-\.]+$');
    if (!urlRegExp.hasMatch(newBaseUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("URL inválida")),
      );
      return;
    }

    final portNumber = int.tryParse(port);
    if (portNumber == null || portNumber < 1 || portNumber > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Porta inválida (1-65535)")),
      );
      return;
    }

    final finalBaseUrl =
        '${_isSslEnabled ? 'https://' : 'http://'}$newBaseUrl:$port';

    await _salvarNovaConexao(newBaseUrl, port, _isSslEnabled);

    // ⚠️ Limpa cache de autorização e força nova validação ao trocar de conexão
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('accessAuthorized');
    prefs.remove('lastValidationTimestamp');

    final success = await ConfigService.saveConfig(finalBaseUrl, '', '');

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Configuração salva. Agora faça login.")),
      );
      if (mounted) {
        await _carregarConexoes(); // <- Atualiza conexões após salvar
        widget.onConfigUpdated();
        Navigator.of(context).pop(); // fecha o diálogo
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Erro ao salvar configurações.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return AlertDialog(
      title: const Text(
        'Credenciais de Conexão',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF2E7D32),
        ),
      ),
      backgroundColor: Colors.white,
      content: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  key: _fieldKey,
                  controller: _baseUrlController,
                  decoration: InputDecoration(
                    labelText: 'Endereço do Servidor',
                    labelStyle: const TextStyle(color: Color(0xFF2E7D32)),
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    suffixIcon: _conexoes.isNotEmpty
                        ? Builder(
                            builder: (context) => IconButton(
                              icon: const Icon(Icons.expand_more, color: Color(0xFF2E7D32)),
                              onPressed: () {
                                final RenderBox renderBox = _fieldKey.currentContext!.findRenderObject() as RenderBox;
                                final Offset offset = renderBox.localToGlobal(Offset.zero);
                                final Size size = renderBox.size;

                                showMenu<String>(
                                  context: context,
                                  position: RelativeRect.fromLTRB(
                                    offset.dx,
                                    offset.dy + size.height,
                                    offset.dx + size.width,
                                    offset.dy + size.height + 300,
                                  ),
                                  items: _conexoes.map((con) {
                                    final host = con['host'].toString();
                                    return PopupMenuItem<String>(
                                      value: host,
                                      child: Text(
                                        con['nomeCurto'] ?? host,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                ).then((selectedHost) {
                                  if (selectedHost != null) {
                                    final selecionada = _conexoes.firstWhere((c) => c['host'] == selectedHost);
                                    setState(() {
                                      _baseUrlController.text = selecionada['host'];
                                      _baseUrlController.selection = TextSelection.collapsed(offset: 0); // mostra início do texto
                                      _portController.text = selecionada['porta'];
                                      _isSslEnabled = selecionada['usarSsl'] == 'true';
                                      _configAlterada = true;
                                    });
                                    FocusScope.of(context).unfocus();
                                  }
                                });
                              },
                            ),
                          )
                        : null,
                  ),
                  style: const TextStyle(color: Colors.black87),
                  onChanged: (_) => setState(() => _configAlterada = true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Porta',
                          labelStyle: const TextStyle(color: Color(0xFF2E7D32)),
                          filled: true,
                          fillColor: Colors.white,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        style: const TextStyle(color: Colors.black87),
                        onChanged: (_) => setState(() => _configAlterada = true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Switch(
                            value: _isSslEnabled,
                            onChanged: (value) => setState(() {
                              _isSslEnabled = value;
                              _configAlterada = true;
                            }),
                            activeColor: const Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Usar SSL',
                            style: TextStyle(fontSize: 16, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _saveConfig,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFF2E7D32)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Salvar',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextButton(
                        onPressed: (_temConfiguracaoSalva && !_configAlterada)
                            ? () => Navigator.of(context).pop()
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFF2E7D32)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Resetar App?', style: TextStyle(color: Color(0xFF2E7D32))),
                                  content: const Text('Isso apagará todas as configurações, tokens e dados de login.\nDeseja continuar?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Resetar')),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.clear();
                              const storage = FlutterSecureStorage();
                              await storage.deleteAll();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('✅ Configurações apagadas. Feche e abra o app para reconfigurar.')),
                                );
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text(
                              'Resetar App',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                        const WidgetSpan(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text('      ', style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              final host = _baseUrlController.text.trim();
                              final port = _portController.text.trim();
                              final conexaoAtual = _conexoes.firstWhere(
                                (c) => c['host'] == host && c['porta'] == port,
                                orElse: () => {},
                              );
                              if (conexaoAtual.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('❌ Conexão atual não localizada para exclusão.')),
                                );
                                return;
                              }
                              final confirmar = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Excluir Conexão'),
                                  content: Text('Deseja excluir a conexão "${conexaoAtual['host']}"?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
                                  ],
                                ),
                              );
                              if (confirmar == true) {
                                final prefs = await SharedPreferences.getInstance();
                                final conexoes = prefs.getStringList('conexoes_salvas') ?? [];
                                conexoes.removeWhere((c) {
                                  final conn = jsonDecode(c);
                                  return conn['host'] == host && conn['porta'] == port;
                                });
                                await prefs.setStringList('conexoes_salvas', conexoes);
                                await _carregarConexoes();
                                setState(() {
                                  _baseUrlController.clear();
                                  _portController.clear();
                                  _isSslEnabled = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('🗑️ Conexão excluída com sucesso')),
                                );
                              }
                            },
                            child: const Text(
                              'Excluir Conexão',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

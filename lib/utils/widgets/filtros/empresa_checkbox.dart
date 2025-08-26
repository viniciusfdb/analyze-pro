import 'package:flutter/material.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

class EmpresaCheckboxFilter extends StatelessWidget {
  final List<Empresa> empresas;
  final List<Empresa> empresasSelecionadas;
  final ValueChanged<List<Empresa>> onSelecionarEmpresas;

  const EmpresaCheckboxFilter({
    super.key,
    required this.empresas,
    required this.empresasSelecionadas,
    required this.onSelecionarEmpresas,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        final selecionadas = await showDialog<List<Empresa>>(
          context: context,
          builder: (context) {
            final List<Empresa> tempSelecionadas = [...empresasSelecionadas];
            return StatefulBuilder(
              builder: (context, setStateDialog) {
                bool todasSelecionadas = tempSelecionadas.length == empresas.length;
                return AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text('Selecionar Empresas'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        CheckboxListTile(
                          value: todasSelecionadas,
                          title: const Text('Todas as Empresas'),
                          activeColor: const Color(0xFF2E7D32),
                          checkColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                          onChanged: (checked) {
                            setStateDialog(() {
                              if (checked == true) {
                                tempSelecionadas.clear();
                                tempSelecionadas.addAll(empresas);
                              } else {
                                tempSelecionadas.clear();
                              }
                            });
                          },
                        ),
                        ...empresas.map((empresa) {
                          final selecionada = tempSelecionadas.any((e) => e.id == empresa.id);
                          return CheckboxListTile(
                            value: selecionada,
                            title: Text(empresa.nome ?? 'Empresa ${empresa.id}'),
                            activeColor: const Color(0xFF2E7D32),
                            checkColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                            onChanged: (checked) {
                              setStateDialog(() {
                                if (checked == true) {
                                  if (!tempSelecionadas.any((e) => e.id == empresa.id)) {
                                    tempSelecionadas.add(empresa);
                                  }
                                } else {
                                  tempSelecionadas.removeWhere((e) => e.id == empresa.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, tempSelecionadas),
                      child: const Text('Aplicar'),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (selecionadas != null) {
          onSelecionarEmpresas(selecionadas);
        }
      },
      icon: const Icon(Icons.business, size: 18, color: Colors.black87),
      label: SizedBox(
        width: double.infinity,
        child: Text(
          empresasSelecionadas.isEmpty || empresasSelecionadas.length == empresas.length
              ? 'Todas as Empresas'
              : empresasSelecionadas.map((e) => e.nome).join(', '),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: Colors.grey.shade200,
        foregroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}
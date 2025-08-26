import 'package:flutter/material.dart';
import 'package:analyzepro/models/cadastros/cad_lojas.dart';

class EmpresaFilter extends StatelessWidget {
  final List<Empresa> empresas;
  final Empresa? empresaSelecionada;
  final ValueChanged<Empresa> onEmpresaSelecionada;

  const EmpresaFilter({
    super.key,
    required this.empresas,
    required this.empresaSelecionada,
    required this.onEmpresaSelecionada,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Empresa>(
      color: Colors.white,
      itemBuilder: (context) {
        return empresas.map((empresa) {
          return PopupMenuItem<Empresa>(
            value: empresa,
            child: Text('${empresa.id} - ${empresa.nome}'),
          );
        }).toList();
      },
      onSelected: onEmpresaSelecionada,
      tooltip: 'Selecionar empresa',
      child: TextButton.icon(
        onPressed: null,
        icon: const Icon(Icons.business, size: 18, color: Color(0xFF2E7D32)),
        label: Text(
          empresaSelecionada?.nome ?? 'Empresa',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF2E7D32)),
        ),
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFE0F2F1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }
}

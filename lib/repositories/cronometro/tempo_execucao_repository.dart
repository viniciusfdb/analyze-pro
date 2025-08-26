import '../../database/database_helper.dart';

class TempoExecucaoRepository {
  final String _tableName = 'tempos_execucao';

  Future<void> salvarTempo(String chave, int tempoMs) async {
    final db = await DatabaseHelper.instance.database;

    final result = await db.query(
      _tableName,
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final totalExecucoes = result.first['total_execucoes'] as int;
      final somaTemposMs = result.first['soma_tempos_ms'] as int;

      await db.update(
        _tableName,
        {
          'total_execucoes': totalExecucoes + 1,
          'soma_tempos_ms': somaTemposMs + tempoMs,
          'ultimo_tempo_ms': tempoMs,
        },
        where: 'chave = ?',
        whereArgs: [chave],
      );
    } else {
      await db.insert(_tableName, {
        'chave': chave,
        'total_execucoes': 1,
        'soma_tempos_ms': tempoMs,
        'ultimo_tempo_ms': tempoMs,
      });
    }
  }

  Future<double?> buscarTempoMedio(String chave) async {
    final db = await DatabaseHelper.instance.database;

    final result = await db.query(
      _tableName,
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final totalExecucoes = result.first['total_execucoes'] as int;
      final somaTemposMs = result.first['soma_tempos_ms'] as int;

      if (totalExecucoes > 0) {
        return somaTemposMs / totalExecucoes / 1000; // retorna em segundos
      }
    }

    return null;
  }

  Future<double?> buscarUltimoTempo(String chave) async {
    final db = await DatabaseHelper.instance.database;

    final result = await db.query(
      _tableName,
      columns: ['ultimo_tempo_ms'],
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final tempoMs = result.first['ultimo_tempo_ms'] as int?;
      return tempoMs != null ? tempoMs / 1000 : null; // retorna em segundos
    }

    return null;
  }
}
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Retorna a instância do banco de dados, inicializando se necessário
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('analyze.db');
    return _database!;
  }

  /// Cria o arquivo .db e abre a conexão
  Future<Database> _initDB(String filePath) async {
    Directory documentsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDir.path, filePath);
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createDB,
    );
  }

  /// Cria as tabelas necessárias
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tempos_execucao (
        chave TEXT PRIMARY KEY,
        total_execucoes INTEGER,
        soma_tempos_ms INTEGER,
        ultimo_tempo_ms INTEGER
      )
    ''');
  }
}

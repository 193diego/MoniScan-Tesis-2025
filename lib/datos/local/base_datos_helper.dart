// lib/datos/local/base_datos_helper.dart
// ✅ SCHEMA COMPATIBLE CON TU MODELO ACTUAL
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../modelos/deteccion.dart';
import '../modelos/usuario.dart';
import '../../config/constantes.dart';

class BaseDatosHelper {
  static final BaseDatosHelper _instance = BaseDatosHelper._internal();
  static Database? _database;

  factory BaseDatosHelper() => _instance;
  BaseDatosHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), Constantes.nombreBaseDatos);
    return await openDatabase(
      path,
      version: 6, // ✅ VERSIÓN 6
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('🔨 Creando base de datos versión $version');

    // Tabla USUARIOS
    await db.execute('''
      CREATE TABLE ${Constantes.tablaUsuarios} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cedula TEXT NOT NULL UNIQUE,
        nombres TEXT NOT NULL,
        apellidos TEXT NOT NULL,
        correo TEXT,
        telefono TEXT,
        direccion TEXT,
        rol TEXT,
        ruta_foto TEXT,
        fecha_registro TEXT,
        fecha_actualizacion TEXT
      )
    ''');

    // Tabla DETECCIONES - ✅ NOMBRES QUE USA TU MODELO
    await db.execute('''
      CREATE TABLE ${Constantes.tablaDetecciones} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        idMazorca TEXT,
        grupoImagen TEXT,
        idUsuario TEXT NOT NULL,
        workerId TEXT,
        fase TEXT NOT NULL,
        confianza REAL NOT NULL,
        severidad INTEGER NOT NULL,
        colorSemaforo TEXT NOT NULL,
        rutaImagen TEXT NOT NULL,
        fecha TEXT NOT NULL,
        latitud REAL,
        longitud REAL,
        direccion TEXT,
        lote TEXT,
        notas TEXT,
        sincronizado INTEGER DEFAULT 0,
        loteId TEXT,
        enSeguimiento INTEGER DEFAULT 0,
        tratamientoId TEXT,
        precisionGPS REAL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_detecciones_usuario ON ${Constantes.tablaDetecciones}(idUsuario)
    ''');

    await db.execute('''
      CREATE INDEX idx_detecciones_sincronizado ON ${Constantes.tablaDetecciones}(sincronizado)
    ''');

    debugPrint('✅ Base de datos creada');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Migrando de v$oldVersion a v$newVersion');

    await db.execute('DROP TABLE IF EXISTS ${Constantes.tablaDetecciones}');

    await db.execute('''
      CREATE TABLE ${Constantes.tablaDetecciones} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        idMazorca TEXT,
        grupoImagen TEXT,
        idUsuario TEXT NOT NULL,
        workerId TEXT,
        fase TEXT NOT NULL,
        confianza REAL NOT NULL,
        severidad INTEGER NOT NULL,
        colorSemaforo TEXT NOT NULL,
        rutaImagen TEXT NOT NULL,
        fecha TEXT NOT NULL,
        latitud REAL,
        longitud REAL,
        direccion TEXT,
        lote TEXT,
        notas TEXT,
        sincronizado INTEGER DEFAULT 0,
        loteId TEXT,
        enSeguimiento INTEGER DEFAULT 0,
        tratamientoId TEXT,
        precisionGPS REAL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_detecciones_usuario ON ${Constantes.tablaDetecciones}(idUsuario)
    ''');

    await db.execute('''
      CREATE INDEX idx_detecciones_sincronizado ON ${Constantes.tablaDetecciones}(sincronizado)
    ''');

    debugPrint('✅ Migración completada');
  }

  // ==================== USUARIOS ====================

  Future<int> insertarUsuario(Usuario usuario) async {
    final db = await database;
    try {
      return await db.insert(
        Constantes.tablaUsuarios,
        usuario.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('❌ Error insertando usuario: $e');
      rethrow;
    }
  }

  Future<Usuario?> obtenerUsuarioPorCedula(String cedula) async {
    final db = await database;
    final maps = await db.query(
      Constantes.tablaUsuarios,
      where: 'cedula = ?',
      whereArgs: [cedula],
    );
    if (maps.isNotEmpty) {
      return Usuario.desdeMap(maps.first);
    }
    return null;
  }

  Future<int> actualizarUsuario(Usuario usuario) async {
    final db = await database;
    return await db.update(
      Constantes.tablaUsuarios,
      usuario.toMap(),
      where: 'cedula = ?',
      whereArgs: [usuario.cedula],
    );
  }

  Future<int> eliminarUsuario(String cedula) async {
    final db = await database;
    return await db.delete(
      Constantes.tablaUsuarios,
      where: 'cedula = ?',
      whereArgs: [cedula],
    );
  }

  // ==================== DETECCIONES ====================

  Future<int> insertarDeteccion(Deteccion deteccion) async {
    final db = await database;
    try {
      final mapa = deteccion.toMap();
      mapa.remove('id');

      final id = await db.insert(
        Constantes.tablaDetecciones,
        mapa,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      debugPrint('✅ Detección insertada con ID: $id');
      return id;
    } catch (e) {
      debugPrint('❌ Error insertando detección: $e');
      debugPrint('📋 Datos: ${deteccion.toMap()}');
      rethrow;
    }
  }

  Future<List<Deteccion>> obtenerDeteccionesPorGrupo(String grupoImagen) async {
    final db = await database;
    final maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'grupoImagen = ?',
      whereArgs: [grupoImagen],
      orderBy: 'fecha DESC',
    );
    return maps.map((m) => Deteccion.fromMap(m)).toList();
  }

  Future<List<Deteccion>> obtenerDeteccionesPorMazorca(String idMazorca) async {
    final db = await database;
    final maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'idMazorca = ?',
      whereArgs: [idMazorca],
      orderBy: 'fecha DESC',
    );
    return maps.map((m) => Deteccion.fromMap(m)).toList();
  }

  Future<List<Deteccion>> obtenerTodasDetecciones(String idUsuario) async {
    final db = await database;
    final maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'idUsuario = ?',
      whereArgs: [idUsuario],
      orderBy: 'fecha DESC',
    );
    return maps.map((m) => Deteccion.fromMap(m)).toList();
  }

  Future<List<Deteccion>> obtenerDeteccionesNoSincronizadas() async {
    final db = await database;
    final maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'sincronizado = ?',
      whereArgs: [0],
    );
    return maps.map((m) => Deteccion.fromMap(m)).toList();
  }

  Future<int> marcarComoSincronizado(int id) async {
    final db = await database;
    return await db.update(
      Constantes.tablaDetecciones,
      {'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> actualizarDeteccion(Deteccion deteccion) async {
    final db = await database;
    return await db.update(
      Constantes.tablaDetecciones,
      deteccion.toMap(),
      where: 'id = ?',
      whereArgs: [deteccion.id],
    );
  }

  Future<int> eliminarDeteccion(int id) async {
    final db = await database;
    return await db.delete(
      Constantes.tablaDetecciones,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> eliminarDeteccionesPorGrupo(String grupoImagen) async {
    final db = await database;
    return await db.delete(
      Constantes.tablaDetecciones,
      where: 'grupoImagen = ?',
      whereArgs: [grupoImagen],
    );
  }

  Future<int> eliminarDeteccionesPorMazorca(String idMazorca) async {
    final db = await database;
    return await db.delete(
      Constantes.tablaDetecciones,
      where: 'idMazorca = ?',
      whereArgs: [idMazorca],
    );
  }

  Future<int> actualizarRutaImagen(int id, String nuevaRuta) async {
    final db = await database;
    return await db.update(
      Constantes.tablaDetecciones,
      {'rutaImagen': nuevaRuta, 'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> obtenerGruposImagenes(
    String idUsuario,
  ) async {
    final db = await database;
    final detecciones = await db.query(
      Constantes.tablaDetecciones,
      where: 'idUsuario = ?',
      whereArgs: [idUsuario],
      orderBy: 'fecha DESC',
    );

    final Map<String, Map<String, dynamic>> gruposMap = {};

    for (var deteccion in detecciones) {
      final grupoId =
          deteccion['grupoImagen'] as String? ?? 'grupo_${deteccion['id']}';

      if (!gruposMap.containsKey(grupoId)) {
        gruposMap[grupoId] = {
          'grupoImagen': grupoId,
          'imagenUrl': deteccion['rutaImagen'],
          'timestamp': deteccion['fecha'],
          'totalDetecciones': 1,
          'lote': deteccion['lote'],
          'latitud': deteccion['latitud'],
          'longitud': deteccion['longitud'],
        };
      } else {
        gruposMap[grupoId]!['totalDetecciones'] =
            (gruposMap[grupoId]!['totalDetecciones'] as int) + 1;
      }
    }

    return gruposMap.values.toList();
  }

  Future<void> limpiarDetecciones(String idUsuario) async {
    final db = await database;
    await db.delete(
      Constantes.tablaDetecciones,
      where: 'idUsuario = ?',
      whereArgs: [idUsuario],
    );
  }

  // ==================== UTILIDADES ====================

  Future<void> limpiarBaseDatos() async {
    final db = await database;
    await db.delete(Constantes.tablaDetecciones);
    await db.delete(Constantes.tablaUsuarios);
  }

  Future<void> cerrarBaseDatos() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> recrearBaseDatos() async {
    try {
      final path = join(await getDatabasesPath(), Constantes.nombreBaseDatos);
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      await deleteDatabase(path);
      debugPrint('🗑️ Base de datos eliminada');

      _database = await _initDatabase();
      debugPrint('✅ Base de datos recreada');
    } catch (e) {
      debugPrint('❌ Error recreando BD: $e');
      rethrow;
    }
  }
}

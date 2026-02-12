// lib/datos/local/base_datos_helper.dart
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
      version: 3, // ← VERSIÓN 3 para forzar nueva migración
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Crear base de datos (primera vez)
  Future<void> _onCreate(Database db, int version) async {
    debugPrint('🔨 Creando base de datos versión $version');

    // Tabla USUARIOS con TODOS los campos necesarios
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

    // Tabla DETECCIONES
    await db.execute('''
      CREATE TABLE ${Constantes.tablaDetecciones} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_mazorca TEXT NOT NULL,
        grupo_imagen TEXT,
        id_usuario TEXT NOT NULL,
        worker_id TEXT,
        fase TEXT NOT NULL,
        confianza REAL NOT NULL,
        severidad INTEGER NOT NULL,
        color_semaforo TEXT NOT NULL,
        ruta_imagen TEXT NOT NULL,
        latitud REAL,
        longitud REAL,
        direccion TEXT,
        lote TEXT,
        notas TEXT,
        fecha TEXT NOT NULL,
        sincronizado INTEGER DEFAULT 0
      )
    ''');

    debugPrint('✅ Base de datos creada exitosamente');
  }

  /// Migrar base de datos
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('🔄 Migrando base de datos de v$oldVersion a v$newVersion');

    // ==================== MIGRACIÓN v1 → v2 ====================
    if (oldVersion < 2) {
      await _agregarColumna(db, Constantes.tablaUsuarios, 'nombres', 'TEXT');
      await _agregarColumna(db, Constantes.tablaUsuarios, 'apellidos', 'TEXT');
      await _agregarColumna(db, Constantes.tablaUsuarios, 'correo', 'TEXT');
      await _agregarColumna(db, Constantes.tablaUsuarios, 'telefono', 'TEXT');
    }

    // ==================== MIGRACIÓN v2 → v3 ====================
    if (oldVersion < 3) {
      await _agregarColumna(db, Constantes.tablaUsuarios, 'ruta_foto', 'TEXT');
      await _agregarColumna(db, Constantes.tablaUsuarios, 'rol', 'TEXT');
      await _agregarColumna(
        db,
        Constantes.tablaUsuarios,
        'fecha_registro',
        'TEXT',
      );
      await _agregarColumna(
        db,
        Constantes.tablaUsuarios,
        'fecha_actualizacion',
        'TEXT',
      );
    }

    debugPrint('✅ Migración completada');
  }

  /// Helper para agregar columnas de forma segura
  Future<void> _agregarColumna(
    Database db,
    String tabla,
    String columna,
    String tipo,
  ) async {
    try {
      await db.execute('ALTER TABLE $tabla ADD COLUMN $columna $tipo');
      debugPrint('✅ Columna "$columna" agregada a tabla "$tabla"');
    } catch (e) {
      if (e.toString().contains('duplicate column')) {
        debugPrint('⚠️ Columna "$columna" ya existe en tabla "$tabla"');
      } else {
        debugPrint('❌ Error agregando columna "$columna": $e');
      }
    }
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
      debugPrint('📋 Datos del usuario: ${usuario.toMap()}');
      rethrow;
    }
  }

  Future<Usuario?> obtenerUsuarioPorCedula(String cedula) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
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

  // CORREGIR insertarDeteccion para evitar conflicto de ID
  Future<int> insertarDeteccion(Deteccion deteccion) async {
    final db = await database;

    try {
      // CRÍTICO: Verificar si ya existe por idMazorca Y grupoImagen
      final existing = await db.query(
        Constantes.tablaDetecciones,
        where: 'id_mazorca = ? AND grupo_imagen = ?',
        whereArgs: [deteccion.idMazorca, deteccion.grupoImagen],
      );

      if (existing.isNotEmpty) {
        // SI EXISTE: Actualizar usando el ID existente
        final idExistente = existing.first['id'] as int;

        // CREAR MAPA SIN EL CAMPO 'id' para evitar conflicto
        final mapaActualizacion = deteccion.toMap();
        mapaActualizacion.remove('id'); // ELIMINAR ID del mapa

        return await db.update(
          Constantes.tablaDetecciones,
          mapaActualizacion,
          where: 'id = ?',
          whereArgs: [idExistente],
        );
      } else {
        // SI NO EXISTE: Insertar nuevo (sin especificar ID)
        final mapaInsercion = deteccion.toMap();
        mapaInsercion.remove(
          'id',
        ); // DEJAR que SQLite genere el ID automáticamente

        return await db.insert(
          Constantes.tablaDetecciones,
          mapaInsercion,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('❌ Error insertando detección: $e');
      debugPrint('📋 Datos: ${deteccion.toMap()}');
      rethrow;
    }
  }

  Future<List<Deteccion>> obtenerDeteccionesPorGrupo(String grupoImagen) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'grupo_imagen = ?',
      whereArgs: [grupoImagen],
      orderBy: 'fecha DESC',
    );

    return List.generate(maps.length, (i) => Deteccion.desdeMap(maps[i]));
  }

  Future<List<Deteccion>> obtenerDeteccionesPorMazorca(String idMazorca) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'id_mazorca = ?',
      whereArgs: [idMazorca],
      orderBy: 'fecha DESC',
    );

    return List.generate(maps.length, (i) => Deteccion.desdeMap(maps[i]));
  }

  Future<List<Deteccion>> obtenerTodasDetecciones(String idUsuario) async {
    final db = await database;
    final res = await db.query(
      Constantes.tablaDetecciones,
      where: 'id_usuario = ?',
      whereArgs: [idUsuario],
      orderBy: 'fecha DESC',
    );

    return res.map(Deteccion.desdeMap).toList();
  }

  Future<List<Map<String, dynamic>>> obtenerGruposImagenes(
    String idUsuario,
  ) async {
    final db = await database;

    final detecciones = await db.query(
      Constantes.tablaDetecciones,
      where: 'id_usuario = ?',
      whereArgs: [idUsuario],
      orderBy: 'fecha DESC',
    );

    final Map<String, Map<String, dynamic>> gruposMap = {};

    for (var deteccion in detecciones) {
      final grupoImagen = deteccion['grupo_imagen'] as String?;
      if (grupoImagen == null || grupoImagen.isEmpty) continue;

      if (!gruposMap.containsKey(grupoImagen)) {
        gruposMap[grupoImagen] = {
          'grupoImagen': grupoImagen,
          'imagenUrl': deteccion['ruta_imagen'],
          'timestamp': deteccion['fecha'],
          'totalDetecciones': 1,
          'lote': deteccion['lote'],
          'latitud': deteccion['latitud'],
          'longitud': deteccion['longitud'],
        };
      } else {
        gruposMap[grupoImagen]!['totalDetecciones'] =
            (gruposMap[grupoImagen]!['totalDetecciones'] as int) + 1;
      }
    }

    return gruposMap.values.toList();
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

  Future<int> actualizarRutaImagen(int id, String nuevaRuta) async {
    final db = await database;
    return await db.update(
      Constantes.tablaDetecciones,
      {'ruta_imagen': nuevaRuta, 'sincronizado': 1},
      where: 'id = ?',
      whereArgs: [id],
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
      where: 'grupo_imagen = ?',
      whereArgs: [grupoImagen],
    );
  }

  Future<int> eliminarDeteccionesPorMazorca(String idMazorca) async {
    final db = await database;
    return await db.delete(
      Constantes.tablaDetecciones,
      where: 'id_mazorca = ?',
      whereArgs: [idMazorca],
    );
  }

  Future<List<Deteccion>> obtenerDeteccionesNoSincronizadas() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      Constantes.tablaDetecciones,
      where: 'sincronizado = ?',
      whereArgs: [0],
    );

    return List.generate(maps.length, (i) => Deteccion.desdeMap(maps[i]));
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

  Future<void> limpiarDetecciones(String idUsuario) async {
    final db = await database;
    await db.delete(
      Constantes.tablaDetecciones,
      where: 'id_usuario = ?',
      whereArgs: [idUsuario],
    );
    debugPrint('🗑️ Detecciones locales limpiadas para usuario: $idUsuario');
  }

  // ==================== UTILIDADES ====================

  Future<void> limpiarBaseDatos() async {
    final db = await database;
    await db.delete(Constantes.tablaDetecciones);
    await db.delete(Constantes.tablaUsuarios);
  }

  Future<void> cerrarBaseDatos() async {
    final db = await database;
    await db.close();
  }

  /// MÉTODO DE EMERGENCIA: Recrear base de datos desde cero
  Future<void> recrearBaseDatos() async {
    try {
      final path = join(await getDatabasesPath(), Constantes.nombreBaseDatos);

      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      await deleteDatabase(path);
      debugPrint('🗑️ Base de datos eliminada: $path');

      _database = await _initDatabase();
      debugPrint('✅ Base de datos recreada con esquema correcto');
    } catch (e) {
      debugPrint('❌ Error recreando base de datos: $e');
      rethrow;
    }
  }
}

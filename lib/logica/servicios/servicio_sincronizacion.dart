// lib/logica/servicios/servicio_sincronizacion.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import 'servicio_conectividad.dart';

class ServicioSincronizacion {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ServicioConectividad _conectividad = ServicioConectividad();

  bool _sincronizando = false;

  /// Inicializar sincronización automática bidireccional
  void inicializarSincronizacionAutomatica() {
    _conectividad.estadoConexion.listen((tieneConexion) {
      if (tieneConexion && !_sincronizando) {
        debugPrint(
          '📡 Internet detectado - Iniciando sincronización bidireccional',
        );
        sincronizarDesdeFirebase().catchError((e) {
          debugPrint('❌ Error sincronizando desde Firebase: $e');
        });
        sincronizarTodo().catchError((e) {
          debugPrint('❌ Error sincronizando hacia Firebase: $e');
        });
      }
    });
  }

  /// ========================================
  /// SINCRONIZACIÓN FIREBASE → SQLITE
  /// ========================================
  Future<void> sincronizarDesdeFirebase() async {
    try {
      debugPrint('🔄 Iniciando sincronización Firebase → SQLite...');
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        debugPrint('⚠️ Usuario no autenticado');
        return;
      }

      // CORRECCIÓN CRÍTICA: Usar workerId en lugar de idUsuario
      final snapshot = await _firestore
          .collection('detecciones')
          .where('workerId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .get();

      debugPrint(
        '📊 Encontradas ${snapshot.docs.length} detecciones en Firebase',
      );

      await _db.limpiarDetecciones(uid);
      debugPrint('🗑️ SQLite limpiado para sincronización');

      int sincronizadas = 0;
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();

          if (data['idMazorca'] == null ||
              data['workerId'] == null ||
              data['fase'] == null ||
              data['imagenUrl'] == null) {
            debugPrint(
              '⚠️ Documento ${doc.id} tiene datos incompletos, se omite',
            );
            continue;
          }

          final deteccion = Deteccion(
            idMazorca: data['idMazorca'] as String,
            grupoImagen: data['grupoImagen'] as String?,
            idUsuario: data['workerCedula'] as String? ?? '',
            workerId: data['workerId'] as String,
            fase: data['fase'] as String,
            confianza: (data['confianza'] as num).toDouble(),
            severidad: data['severidad'] as int,
            colorSemaforo: data['colorSemaforo'] as String,
            rutaImagen: data['imagenUrl'] as String,
            latitud: (data['latitud'] as num?)?.toDouble() ?? 0.0,
            longitud: (data['longitud'] as num?)?.toDouble() ?? 0.0,
            direccion: data['direccion'] as String?,
            lote: data['lote'] as String?,
            notas: data['notas'] as String?,
            fecha:
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            sincronizado: true,
          );

          await _db.insertarDeteccion(deteccion);
          sincronizadas++;
        } catch (e) {
          debugPrint('❌ Error procesando documento ${doc.id}: $e');
        }
      }

      debugPrint(
        '✅ Sincronización completada: $sincronizadas registros descargados',
      );
    } catch (e) {
      debugPrint('❌ Error en sincronización desde Firebase: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  /// ========================================
  /// SINCRONIZACIÓN SQLITE → FIREBASE
  /// ========================================
  Future<void> sincronizarTodo() async {
    if (_sincronizando) {
      debugPrint('⚠️ Ya hay una sincronización en curso');
      return;
    }

    if (!_conectividad.tieneConexion) {
      debugPrint('⚠️ Sin conexión a internet - Sincronización pospuesta');
      return;
    }

    _sincronizando = true;
    try {
      final pendientes = await _db.obtenerDeteccionesNoSincronizadas();

      if (pendientes.isEmpty) {
        debugPrint('ℹ️ No hay detecciones pendientes de sincronización');
        return;
      }

      debugPrint(
        '🔄 Sincronizando ${pendientes.length} detecciones hacia Firebase...',
      );

      for (final deteccion in pendientes) {
        try {
          if (!_conectividad.tieneConexion) break;

          await _sincronizarDeteccion(deteccion);
          await _db.marcarComoSincronizado(deteccion.id!);
          debugPrint('✅ Detección ${deteccion.id} sincronizada');
        } catch (e) {
          debugPrint('❌ Error sincronizando detección: $e');
        }
      }
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> _sincronizarDeteccion(Deteccion deteccion) async {
    String imagenUrl = deteccion.rutaImagen;

    if (!imagenUrl.startsWith('http')) {
      imagenUrl = await _subirImagenAStorage(
        rutaLocal: deteccion.rutaImagen,
        idUsuario: deteccion.idUsuario,
        idMazorca: deteccion.idMazorca,
      );
    }

    await _guardarEnFirestore(deteccion, imagenUrl);
    await _db.actualizarRutaImagen(deteccion.id!, imagenUrl);
  }

  Future<String> _subirImagenAStorage({
    required String rutaLocal,
    required String idUsuario,
    required String idMazorca,
  }) async {
    final archivo = File(rutaLocal);
    final workerId = _auth.currentUser?.uid;

    if (workerId == null) throw Exception('Usuario no autenticado');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nombreArchivo = '${idMazorca}_$timestamp.jpg';
    final rutaStorage = 'detecciones/$workerId/$nombreArchivo';

    final storageRef = _storage.ref().child(rutaStorage);
    final snapshot = await storageRef.putFile(
      archivo,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _guardarEnFirestore(
    Deteccion deteccion,
    String imagenUrl,
  ) async {
    final workerId = _auth.currentUser?.uid;
    if (workerId == null) throw Exception('Usuario no autenticado');

    String workerNombre = _auth.currentUser?.email ?? 'Desconocido';
    try {
      final workerDoc = await _firestore
          .collection('workers')
          .doc(workerId)
          .get();
      if (workerDoc.exists) {
        workerNombre = workerDoc.data()?['name'] ?? workerNombre;
      }
    } catch (_) {}

    // CORRECCIÓN CRÍTICA: Usar workerId como clave principal
    await _firestore.collection('detecciones').add({
      'idMazorca': deteccion.idMazorca,
      'grupoImagen': deteccion.grupoImagen,
      'idUsuario': deteccion.idUsuario,
      'workerId': workerId, // ✅ CRÍTICO: Este campo se usa en las reglas
      'workerCedula': deteccion.idUsuario,
      'workerNombre': workerNombre,
      'fase': deteccion.fase,
      'confianza': deteccion.confianza,
      'severidad': deteccion.severidad,
      'colorSemaforo': deteccion.colorSemaforo,
      'imagenUrl': imagenUrl,
      'latitud': deteccion.latitud,
      'longitud': deteccion.longitud,
      'direccion': deteccion.direccion,
      'lote': deteccion.lote,
      'notas': deteccion.notas,
      'fecha': Timestamp.fromDate(deteccion.fecha),
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'sincronizado': true,
    });
  }

  Future<String> sincronizarDeteccionInmediata({
    required Deteccion deteccion,
    required File imagenFile,
  }) async {
    if (!_conectividad.tieneConexion) {
      throw Exception('Sin conexión a internet');
    }

    final imagenUrl = await _subirImagenDirecta(
      archivo: imagenFile,
      idUsuario: deteccion.idUsuario,
      idMazorca: deteccion.idMazorca,
    );

    await _guardarEnFirestore(deteccion, imagenUrl);

    return imagenUrl;
  }

  Future<String> _subirImagenDirecta({
    required File archivo,
    required String idUsuario,
    required String idMazorca,
  }) async {
    final workerId = _auth.currentUser?.uid;
    if (workerId == null) throw Exception('Usuario no autenticado');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nombreArchivo = '${idMazorca}_$timestamp.jpg';
    final rutaStorage = 'detecciones/$workerId/$nombreArchivo';

    final storageRef = _storage.ref().child(rutaStorage);
    final snapshot = await storageRef.putFile(
      archivo,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await snapshot.ref.getDownloadURL();
  }

  Future<int> obtenerCantidadPendientes() async {
    final pendientes = await _db.obtenerDeteccionesNoSincronizadas();
    return pendientes.length;
  }
}

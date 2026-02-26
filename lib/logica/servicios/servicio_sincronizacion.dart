// lib/logica/servicios/servicio_sincronizacion.dart
// ✅ VERSIÓN CORREGIDA — SINCRONIZACIÓN WEB + MÓVIL
// CAMBIOS RESPECTO A LA VERSIÓN ANTERIOR:
// 1. _guardarEnFirestore() → AÑADIDO 'idMazorca' al mapa que sube a Firestore.
//    Ahora la web puede agrupar seguimientos por idMazorca.
// 2. sincronizarDesdeFirebase() → Lee 'idMazorca' y 'grupoImagen' desde Firestore
//    en vez de usar doc.id como idMazorca (era incorrecto y rompía el seguimiento).

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import 'servicio_conectividad.dart';
import '../../config/constantes.dart';

class ServicioSincronizacion {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ServicioConectividad _conectividad = ServicioConectividad();

  bool _sincronizando = false;

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

  // ─── Sincronización Firebase → SQLite ────────────────────────────────────────

  Future<void> sincronizarDesdeFirebase() async {
    try {
      debugPrint('🔄 Iniciando sincronización Firebase → SQLite...');
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        debugPrint('⚠️ Usuario no autenticado');
        return;
      }

      final snapshot = await _firestore
          .collection(Constantes.coleccionDetecciones)
          .where('trabajadorUID', isEqualTo: uid)
          .orderBy('fechaDeteccion', descending: true)
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

          // Validar campos mínimos requeridos del diccionario
          if (data['trabajadorUID'] == null ||
              data['nombreFaseDetectada'] == null ||
              data['imagenURL'] == null) {
            debugPrint(
              '⚠️ Documento ${doc.id} tiene datos incompletos, se omite',
            );
            continue;
          }

          // El campo nombreFaseDetectada puede venir como "Fase Inicial" o "FASE_INICIAL"
          final String faseFirestore = data['nombreFaseDetectada'] as String;
          final String faseNormalizada = _normalizarFaseDesdeFirestore(
            faseFirestore,
          );

          // ✅ CORRECCIÓN: leer idMazorca desde Firestore (antes se usaba doc.id
          // lo cual rompía el seguimiento al re-sincronizar porque el idMazorca
          // no coincidía con el original guardado en SQLite).
          // Fallback a doc.id solo para registros viejos que no tienen el campo.
          final String idMazorcaReal =
              (data['idMazorca'] as String?)?.isNotEmpty == true
              ? data['idMazorca'] as String
              : doc.id;

          // ✅ CORRECCIÓN: también leer grupoImagen desde Firestore
          final String? grupoImagenReal =
              (data['grupoImagen'] as String?)?.isNotEmpty == true
              ? data['grupoImagen'] as String
              : null;

          final deteccion = Deteccion(
            idMazorca: idMazorcaReal,
            grupoImagen: grupoImagenReal,
            idUsuario: uid,
            workerId: uid,
            fase: faseNormalizada,
            confianza: ((data['porcentajeInfeccion'] as num?) ?? 0) / 100,
            severidad: (data['faseDetectada'] as int?) ?? 0,
            colorSemaforo: data['colorSemaforo'] as String? ?? 'verde',
            rutaImagen: data['imagenURL'] as String? ?? '',
            latitud: (data['latitud'] as num?)?.toDouble() ?? 0.0,
            longitud: (data['longitud'] as num?)?.toDouble() ?? 0.0,
            lote: data['loteNombre'] as String?,
            notas: data['observaciones'] as String?,
            fecha:
                (data['fechaDeteccion'] as Timestamp?)?.toDate() ??
                DateTime.now(),
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
    }
  }

  String _normalizarFaseDesdeFirestore(String faseFirestore) {
    // Si ya es formato YOLO, devolver tal cual
    if (Constantes.nombresClases.contains(faseFirestore)) {
      return faseFirestore;
    }

    // Mapear formato legible → formato YOLO
    const mapa = {
      'Sana': 'SANA',
      'sana': 'SANA',
      'Fase Inicial': 'FASE_INICIAL',
      'fase inicial': 'FASE_INICIAL',
      'Temprana': 'FASE_INICIAL',
      'Fase Intermedia': 'FASE_INTERMEDIA',
      'fase intermedia': 'FASE_INTERMEDIA',
      'Intermedia': 'FASE_INTERMEDIA',
      'Fase Avanzada': 'FASE_AVANZADA',
      'fase avanzada': 'FASE_AVANZADA',
      'Avanzada': 'FASE_AVANZADA',
    };

    return mapa[faseFirestore] ?? 'SANA';
  }

  // ─── Sincronización SQLite → Firebase ────────────────────────────────────────

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
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    final rutaStorage =
        '${Constantes.carpetaImagenesDetecciones}/$workerId/$fecha/mazorca_$timestamp.jpg';

    final storageRef = _storage.ref().child(rutaStorage);
    final snapshot = await storageRef.putFile(
      archivo,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await snapshot.ref.getDownloadURL();
  }

  // ✅ MÉTODO PÚBLICO para subir imágenes desde escaneo inmediato
  Future<String> subirImagenPublica({
    required File archivoLocal,
    required String workerId,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    final rutaStorage =
        '${Constantes.carpetaImagenesDetecciones}/$workerId/$fecha/mazorca_$timestamp.jpg';

    final storageRef = _storage.ref().child(rutaStorage);
    final snapshot = await storageRef.putFile(
      archivoLocal,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final url = await snapshot.ref.getDownloadURL();
    debugPrint('✅ Imagen subida: $url');
    return url;
  }

  // ─── Guardar en Firestore ─────────────────────────────────────────────────────
  //
  // Campos que se guardan:
  //   ✅ trabajadorUID, trabajadorNombre
  //   ✅ nombreFaseDetectada, faseDetectada, porcentajeInfeccion
  //   ✅ imagenURL, loteNombre, colorSemaforo, observaciones
  //   ✅ latitud, longitud, fechaDeteccion
  //   ✅ grupoImagen  → agrupa bounding boxes de la misma captura
  //   ✅ idMazorca    → identifica la mazorca única para seguimiento en web
  //
  Future<void> _guardarEnFirestore(
    Deteccion deteccion,
    String imagenUrl,
  ) async {
    final workerId = _auth.currentUser?.uid;
    if (workerId == null) throw Exception('Usuario no autenticado');

    // Obtener nombre del trabajador desde Firestore
    String workerNombre = _auth.currentUser?.email ?? 'Desconocido';
    try {
      final workerDoc = await _firestore
          .collection(Constantes.coleccionUsuarios)
          .doc(workerId)
          .get();
      if (workerDoc.exists) {
        workerNombre = workerDoc.data()?['nombreCompleto'] ?? workerNombre;
      }
    } catch (_) {}

    // Convertir fase YOLO a valores del diccionario
    final String nombreFaseLegible = Constantes.obtenerNombreLegible(
      deteccion.fase,
    );
    final int numeroFase = Constantes.obtenerNumeroFaseFirestore(
      deteccion.fase,
    );

    debugPrint('📝 Guardando en Firestore:');
    debugPrint('   trabajadorUID      : $workerId');
    debugPrint('   trabajadorNombre   : $workerNombre');
    debugPrint('   nombreFaseDetectada: $nombreFaseLegible');
    debugPrint('   faseDetectada      : $numeroFase');
    debugPrint(
      '   porcentajeInfeccion: ${(deteccion.confianza * 100).toStringAsFixed(1)}%',
    );
    debugPrint('   colorSemaforo      : ${deteccion.colorSemaforo}');
    debugPrint('   loteNombre         : ${deteccion.lote ?? "(sin lote)"}');
    debugPrint(
      '   grupoImagen        : ${deteccion.grupoImagen ?? "(sin grupo)"}',
    );
    debugPrint('   idMazorca          : ${deteccion.idMazorca}'); // ✅ nuevo log

    await _firestore.collection(Constantes.coleccionDetecciones).add({
      'trabajadorUID': workerId,
      'trabajadorNombre': workerNombre,
      'nombreFaseDetectada': nombreFaseLegible,
      'faseDetectada': numeroFase,
      'porcentajeInfeccion': deteccion.confianza * 100,
      'imagenURL': imagenUrl,
      'loteNombre': deteccion.lote ?? '',
      'colorSemaforo': deteccion.colorSemaforo,
      'observaciones': deteccion.notas ?? '',
      'latitud': deteccion.latitud,
      'longitud': deteccion.longitud,
      'fechaDeteccion': Timestamp.fromDate(deteccion.fecha),
      'grupoImagen': deteccion.grupoImagen ?? '',
      'idMazorca':
          deteccion.idMazorca, // ✅ CAMPO NUEVO — clave para seguimiento web
    });

    debugPrint('✅ Detección guardada en Firestore correctamente');
  }

  // ─── Sincronización inmediata (con conexión activa) ───────────────────────────

  Future<String> sincronizarDeteccionInmediata({
    required Deteccion deteccion,
  }) async {
    if (!_conectividad.tieneConexion) {
      throw Exception('Sin conexión a internet');
    }

    String imagenUrl = deteccion.rutaImagen;

    if (!imagenUrl.startsWith('http')) {
      imagenUrl = await _subirImagenAStorage(
        rutaLocal: deteccion.rutaImagen,
        idUsuario: deteccion.idUsuario,
        idMazorca: deteccion.idMazorca,
      );
    }

    await _guardarEnFirestore(deteccion, imagenUrl);

    if (deteccion.id != null) {
      await _db.marcarComoSincronizado(deteccion.id!);
      await _db.actualizarRutaImagen(deteccion.id!, imagenUrl);
    }

    return imagenUrl;
  }

  // ─── Eliminar detección de Firebase ──────────────────────────────────────────

  Future<void> eliminarDeteccionFirebase(String idMazorca) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // ✅ Ahora sí funciona porque idMazorca existe en Firestore
      final query = await _firestore
          .collection(Constantes.coleccionDetecciones)
          .where('trabajadorUID', isEqualTo: uid)
          .where('idMazorca', isEqualTo: idMazorca)
          .get();

      for (var doc in query.docs) {
        await doc.reference.delete();
        debugPrint('🗑️ Detección ${doc.id} eliminada de Firebase');
      }
    } catch (e) {
      debugPrint('❌ Error eliminando detección de Firebase: $e');
    }
  }

  // ─── Obtener tratamiento recomendado desde colección "tratamientos" ───────────
  //
  // El campo 'fase' en Firestore debe coincidir EXACTAMENTE con la etiqueta YOLO.
  // La administradora debe crear protocolos con fase:
  //   "SANA" | "FASE_INICIAL" | "FASE_INTERMEDIA" | "FASE_AVANZADA"
  //
  Future<Map<String, dynamic>?> obtenerTratamientoRecomendado(
    String fase,
  ) async {
    try {
      debugPrint('🔍 Buscando tratamiento para fase: $fase');

      final query = await _firestore
          .collection(Constantes.coleccionTratamientos)
          .where('fase', isEqualTo: fase)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        debugPrint('✅ Tratamiento encontrado: ${data['nombre']}');
        return data;
      }

      debugPrint('⚠️ No se encontró tratamiento para $fase');
      debugPrint('💡 La administradora debe crear este protocolo en la web');
      debugPrint('💡 El campo "fase" debe ser exactamente: $fase');
      return null;
    } catch (e) {
      debugPrint('❌ Error consultando tratamiento: $e');
      return null;
    }
  }
}

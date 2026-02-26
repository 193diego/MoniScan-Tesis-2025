// lib/logica/servicios/servicio_recomendaciones.dart
// ✅ VERSIÓN CORREGIDA
// PROBLEMA ORIGINAL: consultaba colección 'recomendaciones' que no existe en Firestore.
// CORRECCIÓN: ahora consulta la colección 'tratamientos' (definida en el diccionario de datos),
// usando el campo 'fase' con el valor exacto de la etiqueta YOLO.
// El caché local se mantiene como fallback offline.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../datos/modelos/recomendacion.dart';
import '../../datos/local/recomendaciones_cache.dart';

/// Servicio HÍBRIDO: Firebase (online) + Caché (offline)
class ServicioRecomendaciones {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RecomendacionesCache _cache = RecomendacionesCache();

  // Nombre correcto de la colección según el diccionario de datos
  static const String _coleccion = 'tratamientos';

  /// Obtener protocolo de tratamiento para una fase específica.
  ///
  /// [fase] debe ser una etiqueta YOLO exacta:
  ///   'SANA' | 'FASE_INICIAL' | 'FASE_INTERMEDIA' | 'FASE_AVANZADA'
  ///
  /// 1. Intenta cargar desde Firebase (colección 'tratamientos')
  /// 2. Si falla o no hay resultado, usa caché local como fallback
  Future<List<Recomendacion>> obtenerPorFase(String fase) async {
    try {
      // ✅ CORREGIDO: colección 'tratamientos', campo 'fase' con valor YOLO exacto
      final querySnapshot = await _firestore
          .collection(_coleccion)
          .where('fase', isEqualTo: fase)
          .get()
          .timeout(const Duration(seconds: 5));

      if (querySnapshot.docs.isNotEmpty) {
        debugPrint('✅ Tratamiento cargado desde Firebase para fase: $fase');
        return querySnapshot.docs.map((doc) {
          return Recomendacion.desdeFirestore(doc.data(), doc.id);
        }).toList();
      }

      debugPrint('⚠️ Sin tratamiento en Firebase para "$fase" — usando caché');
    } catch (e) {
      debugPrint('⚠️ Error desde Firebase, usando caché: $e');
    }

    // Fallback a caché local
    debugPrint('📦 Usando recomendaciones desde caché local');
    return _cache.obtenerPorFase(fase);
  }

  /// Obtener todos los protocolos de tratamiento
  Future<List<Recomendacion>> obtenerTodas() async {
    try {
      final querySnapshot = await _firestore
          .collection(_coleccion)
          .get()
          .timeout(const Duration(seconds: 5));

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.map((doc) {
          return Recomendacion.desdeFirestore(doc.data(), doc.id);
        }).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error obteniendo todos los tratamientos: $e');
    }

    return _cache.obtenerTodas();
  }

  /// Stream en tiempo real (solo online)
  Stream<List<Recomendacion>> watchRecomendacionesPorFase(String fase) {
    return _firestore
        .collection(_coleccion)
        .where('fase', isEqualTo: fase)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Recomendacion.desdeFirestore(doc.data(), doc.id);
          }).toList();
        })
        .handleError((error) {
          debugPrint('⚠️ Error en stream de tratamientos: $error');
          return _cache.obtenerPorFase(fase);
        });
  }
}

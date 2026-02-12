// lib/logica/servicios/servicio_recomendaciones.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../datos/modelos/recomendacion.dart';
import '../../datos/local/recomendaciones_cache.dart';

/// Servicio HÍBRIDO: Firebase (online) + Caché (offline)
class ServicioRecomendaciones {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RecomendacionesCache _cache = RecomendacionesCache();

  /// Obtener recomendaciones para una fase específica
  /// 1. Intenta cargar desde Firebase (online)
  /// 2. Si falla, usa caché local (offline)
  Future<List<Recomendacion>> obtenerPorFase(String fase) async {
    try {
      // PASO 1: Intentar desde Firebase
      final querySnapshot = await _firestore
          .collection('recomendaciones')
          .where('fase', isEqualTo: fase)
          .orderBy('prioridad', descending: false)
          .get()
          .timeout(const Duration(seconds: 5));

      if (querySnapshot.docs.isNotEmpty) {
        debugPrint('✅ Recomendaciones cargadas desde Firebase');
        return querySnapshot.docs.map((doc) {
          return Recomendacion.desdeFirestore(doc.data(), doc.id);
        }).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error desde Firebase, usando caché: $e');
    }

    // PASO 2: Fallback a caché local
    debugPrint('📦 Usando recomendaciones desde caché local');
    return _cache.obtenerPorFase(fase);
  }

  /// Obtener todas las recomendaciones (Firebase primero, caché fallback)
  Future<List<Recomendacion>> obtenerTodas() async {
    try {
      final querySnapshot = await _firestore
          .collection('recomendaciones')
          .orderBy('prioridad', descending: false)
          .get()
          .timeout(const Duration(seconds: 5));

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.map((doc) {
          return Recomendacion.desdeFirestore(doc.data(), doc.id);
        }).toList();
      }
    } catch (e) {
      debugPrint('⚠️ Error obteniendo todas las recomendaciones: $e');
    }

    return _cache.obtenerTodas();
  }

  /// Stream de recomendaciones en tiempo real (solo online)
  Stream<List<Recomendacion>> watchRecomendacionesPorFase(String fase) {
    return _firestore
        .collection('recomendaciones')
        .where('fase', isEqualTo: fase)
        .orderBy('prioridad', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Recomendacion.desdeFirestore(doc.data(), doc.id);
          }).toList();
        })
        .handleError((error) {
          debugPrint('⚠️ Error en stream de recomendaciones: $error');
          return _cache.obtenerPorFase(fase);
        });
  }
}

// lib/logica/servicios/servicio_eliminacion.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ AGREGADO
import '../../datos/local/base_datos_helper.dart';

class ServicioEliminacion {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Eliminar grupo de imagen (SINCRONIZADO: Firebase + SQLite)
  Future<bool> eliminarGrupoImagen({
    required String grupoImagen,
    required String idUsuario, // Se mantiene el parámetro por compatibilidad
  }) async {
    try {
      debugPrint('🗑️ Eliminando grupo: $grupoImagen');

      // 1. ELIMINAR DE FIREBASE PRIMERO
      try {
        // ✅ CORRECCIÓN 3: Usar trabajadorUID con el UID de Firebase Auth
        // (antes buscaba por 'idUsuario' con la cédula, nunca encontraba nada)
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          debugPrint(
            '⚠️ Usuario no autenticado, no se puede eliminar de Firebase',
          );
        } else {
          QuerySnapshot snapshot;

          // Buscar por trabajadorUID (campo correcto según el esquema Firestore)
          if (grupoImagen.isNotEmpty) {
            // Filtrar también por grupoImagen si está disponible
            snapshot = await _firestore
                .collection('detecciones')
                .where(
                  'trabajadorUID',
                  isEqualTo: uid,
                ) // ✅ ERA 'idUsuario' con cédula
                .where('grupoImagen', isEqualTo: grupoImagen)
                .get();
          } else {
            snapshot = await _firestore
                .collection('detecciones')
                .where(
                  'trabajadorUID',
                  isEqualTo: uid,
                ) // ✅ ERA 'idUsuario' con cédula
                .get();
          }

          debugPrint(
            '📊 Documentos a eliminar de Firebase: ${snapshot.docs.length}',
          );

          // Eliminar imágenes de Storage
          final imagenesEliminadas = <String>{};
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            // ✅ CORREGIDO: campo correcto es 'imagenURL' (antes era 'imagenUrl')
            final imagenUrl = data['imagenURL'] as String?;
            final imagenPath = data['imagenPath'] as String?;

            // Intentar eliminar por ruta directa (más confiable)
            if (imagenPath != null && imagenPath.isNotEmpty) {
              try {
                await _storage.ref(imagenPath).delete();
                debugPrint('✅ Imagen eliminada por path: $imagenPath');
              } catch (e) {
                debugPrint('⚠️ Error eliminando imagen por path: $e');
              }
            } else if (imagenUrl != null &&
                imagenUrl.isNotEmpty &&
                !imagenesEliminadas.contains(imagenUrl)) {
              try {
                final ref = _storage.refFromURL(imagenUrl);
                await ref.delete();
                imagenesEliminadas.add(imagenUrl);
                debugPrint('✅ Imagen eliminada de Storage: $imagenUrl');
              } catch (e) {
                debugPrint('⚠️ Error eliminando imagen de Storage: $e');
              }
            }
          }

          // Eliminar documentos de Firestore (batch)
          final batch = _firestore.batch();
          for (var doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          debugPrint(
            '✅ ${snapshot.docs.length} documentos eliminados de Firebase',
          );
        }
      } catch (e) {
        debugPrint('❌ Error eliminando de Firebase: $e');
      }

      // 2. ELIMINAR DE SQLITE LOCAL
      await _db.eliminarDeteccionesPorGrupo(grupoImagen);
      debugPrint('✅ Grupo eliminado de SQLite local');

      return true;
    } catch (e) {
      debugPrint('❌ Error eliminando grupo: $e');
      return false;
    }
  }
}

// lib/logica/servicios/servicio_eliminacion.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../datos/local/base_datos_helper.dart';

class ServicioEliminacion {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Eliminar grupo de imagen (SINCRONIZADO: Firebase + SQLite)
  Future<bool> eliminarGrupoImagen({
    required String grupoImagen,
    required String idUsuario,
  }) async {
    try {
      debugPrint('🗑️ Eliminando grupo: $grupoImagen');

      // 1. ELIMINAR DE FIREBASE PRIMERO
      try {
        final snapshot = await _firestore
            .collection('detecciones')
            .where('grupoImagen', isEqualTo: grupoImagen)
            .where('idUsuario', isEqualTo: idUsuario)
            .get();

        debugPrint(
          '📊 Documentos a eliminar de Firebase: ${snapshot.docs.length}',
        );

        // Eliminar imágenes de Storage
        final imagenesEliminadas = <String>{};
        for (var doc in snapshot.docs) {
          final imagenUrl = doc.data()['imagenUrl'] as String?;
          if (imagenUrl != null &&
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

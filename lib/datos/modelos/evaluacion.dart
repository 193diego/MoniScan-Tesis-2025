// lib/datos/modelos/evaluacion.dart
// ✅ NUEVO ARCHIVO - Creado según Corrección 6.2 del PROMPT MAESTRO
import 'package:cloud_firestore/cloud_firestore.dart';

class Evaluacion {
  final String? evalId;
  final String imagenURL; // URL de Storage de la foto de esta evaluación
  final String
  imagenPath; // Ruta en Storage: 'imagenes/seguimientos/{id}/eval_{ts}.jpg'
  final int faseDetectada; // Resultado de YOLOv11 (0-4)
  final double porcentajeInfeccion; // Confianza del modelo × 100
  final String? observaciones;
  final DateTime? fechaEvaluacion;

  Evaluacion({
    this.evalId,
    required this.imagenURL,
    required this.imagenPath,
    required this.faseDetectada,
    required this.porcentajeInfeccion,
    this.observaciones,
    this.fechaEvaluacion,
  });

  Map<String, dynamic> toFirestoreMap() {
    return {
      'imagenURL': imagenURL,
      'imagenPath': imagenPath,
      'faseDetectada': faseDetectada,
      'porcentajeInfeccion': porcentajeInfeccion,
      'observaciones': observaciones,
      'fechaEvaluacion': FieldValue.serverTimestamp(),
    };
  }

  factory Evaluacion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Evaluacion(
      evalId: doc.id,
      imagenURL: data['imagenURL'] as String? ?? '',
      imagenPath: data['imagenPath'] as String? ?? '',
      faseDetectada: (data['faseDetectada'] as int?) ?? 0,
      porcentajeInfeccion:
          (data['porcentajeInfeccion'] as num?)?.toDouble() ?? 0.0,
      observaciones: data['observaciones'] as String?,
      fechaEvaluacion: (data['fechaEvaluacion'] as Timestamp?)?.toDate(),
    );
  }
}

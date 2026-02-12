// lib/datos/modelos/recomendacion.dart
import 'package:flutter/material.dart';

/// Modelo de Recomendación para tratamiento de Moniliasis
class Recomendacion {
  final String? id;
  final String fase;
  final String titulo;
  final String descripcion;
  final List<String> acciones;
  final String? urlImagen;
  final int prioridad; // 1=alta, 2=media, 3=baja
  final DateTime? fechaCreacion;

  Recomendacion({
    this.id,
    required this.fase,
    required this.titulo,
    required this.descripcion,
    required this.acciones,
    this.urlImagen,
    this.prioridad = 2,
    this.fechaCreacion,
  });

  /// Desde Firestore
  factory Recomendacion.desdeFirestore(
    Map<String, dynamic> data,
    String docId,
  ) {
    return Recomendacion(
      id: docId,
      fase: data['fase'] ?? '',
      titulo: data['titulo'] ?? '',
      descripcion: data['descripcion'] ?? '',
      acciones: List<String>.from(data['acciones'] ?? []),
      urlImagen: data['urlImagen'],
      prioridad: data['prioridad'] ?? 2,
      fechaCreacion: data['fechaCreacion']?.toDate(),
    );
  }

  /// A Firestore
  Map<String, dynamic> aFirestore() {
    return {
      'fase': fase,
      'titulo': titulo,
      'descripcion': descripcion,
      'acciones': acciones,
      'urlImagen': urlImagen,
      'prioridad': prioridad,
      'fechaCreacion': fechaCreacion ?? DateTime.now(),
    };
  }

  Color get colorPrioridad {
    switch (prioridad) {
      case 1:
        return const Color(0xFFF44336); // Rojo - Alta
      case 2:
        return const Color(0xFFFF9800); // Naranja - Media
      case 3:
        return const Color(0xFF4CAF50); // Verde - Baja
      default:
        return const Color(0xFF9E9E9E); // Gris
    }
  }

  String get textoPrioridad {
    switch (prioridad) {
      case 1:
        return 'URGENTE';
      case 2:
        return 'IMPORTANTE';
      case 3:
        return 'PREVENTIVO';
      default:
        return 'NORMAL';
    }
  }
}

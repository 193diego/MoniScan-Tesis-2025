// lib/datos/modelos/seguimiento.dart
// ✅ NUEVO ARCHIVO - Creado según Corrección 6.2 del PROMPT MAESTRO
import 'package:cloud_firestore/cloud_firestore.dart';

class Seguimiento {
  final String? seguimientoId;
  final String deteccionOrigenId;
  final String trabajadorUID;
  final String trabajadorNombre;
  final String loteId;
  final String loteNombre;
  final String numeroArbol;
  final GeoPoint? coordenadas; // GeoPoint para el pin en Google Maps
  final double latitud;
  final double longitud;
  final int faseInicial; // Fase de la primera evaluación (no cambia)
  final int faseActual; // Fase de la última evaluación (se actualiza)
  final String colorPinMapa; // 'verde'|'amarillo'|'naranja'|'rojo'|'gris'
  final String estado; // 'activo' | 'controlado' | 'perdido'
  final int totalEvaluaciones;
  final DateTime? fechaInicio;
  final DateTime? ultimaEvaluacion;

  Seguimiento({
    this.seguimientoId,
    required this.deteccionOrigenId,
    required this.trabajadorUID,
    required this.trabajadorNombre,
    required this.loteId,
    required this.loteNombre,
    required this.numeroArbol,
    this.coordenadas,
    required this.latitud,
    required this.longitud,
    required this.faseInicial,
    required this.faseActual,
    required this.colorPinMapa,
    this.estado = 'activo',
    this.totalEvaluaciones = 1,
    this.fechaInicio,
    this.ultimaEvaluacion,
  });

  Map<String, dynamic> toFirestoreMap() {
    return {
      'deteccionOrigenId': deteccionOrigenId,
      'trabajadorUID': trabajadorUID,
      'trabajadorNombre': trabajadorNombre,
      'loteId': loteId,
      'loteNombre': loteNombre,
      'numeroArbol': numeroArbol,
      'coordenadas': GeoPoint(
        latitud,
        longitud,
      ), // ✅ OBLIGATORIO para Google Maps
      'latitud': latitud,
      'longitud': longitud,
      'faseInicial': faseInicial,
      'faseActual': faseActual,
      'colorPinMapa': colorPinMapa,
      'estado': estado,
      'totalEvaluaciones': totalEvaluaciones,
      'fechaInicio': FieldValue.serverTimestamp(),
      'ultimaEvaluacion': FieldValue.serverTimestamp(),
    };
  }

  factory Seguimiento.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Seguimiento(
      seguimientoId: doc.id,
      deteccionOrigenId: data['deteccionOrigenId'] as String? ?? '',
      trabajadorUID: data['trabajadorUID'] as String? ?? '',
      trabajadorNombre: data['trabajadorNombre'] as String? ?? '',
      loteId: data['loteId'] as String? ?? '',
      loteNombre: data['loteNombre'] as String? ?? '',
      numeroArbol: data['numeroArbol'] as String? ?? '',
      coordenadas: data['coordenadas'] as GeoPoint?,
      latitud: (data['latitud'] as num?)?.toDouble() ?? 0.0,
      longitud: (data['longitud'] as num?)?.toDouble() ?? 0.0,
      faseInicial: (data['faseInicial'] as int?) ?? 0,
      faseActual: (data['faseActual'] as int?) ?? 0,
      colorPinMapa: data['colorPinMapa'] as String? ?? 'rojo',
      estado: data['estado'] as String? ?? 'activo',
      totalEvaluaciones: (data['totalEvaluaciones'] as int?) ?? 0,
      fechaInicio: (data['fechaInicio'] as Timestamp?)?.toDate(),
      ultimaEvaluacion: (data['ultimaEvaluacion'] as Timestamp?)?.toDate(),
    );
  }
}

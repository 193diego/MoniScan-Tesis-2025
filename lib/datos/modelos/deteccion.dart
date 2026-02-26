// lib/datos/modelos/deteccion.dart
// ✅ MODELO COMPLETO - Compatible con Firebase y SQLite
class Deteccion {
  final int? id; // ID local SQLite
  final String idMazorca; // ID único de la mazorca (UUID)
  final String? grupoImagen; // Agrupa detecciones de la misma captura
  final String idUsuario; // Cédula del trabajador
  final String? workerId; // UID de Firebase Auth
  final String
  fase; // ✅ ETIQUETA YOLO: 'SANA', 'FASE_INICIAL', 'FASE_INTERMEDIA', 'FASE_AVANZADA'
  final double confianza; // 0.0 a 1.0
  final int severidad; // 0-3
  final String colorSemaforo; // 'verde', 'amarillo', 'naranja', 'rojo'
  final String rutaImagen; // Ruta local o URL de Firebase Storage
  final DateTime fecha;
  final double latitud;
  final double longitud;
  final String? direccion;
  final String? lote; // Nombre del lote
  final String? notas;
  final bool sincronizado; // true si ya está en Firebase

  // Campos adicionales para Firebase
  final String? loteId; // ID del lote en Firestore
  final bool enSeguimiento; // true si tiene seguimiento activo
  final String? tratamientoId; // ID del tratamiento recomendado
  final double? precisionGPS; // Precisión GPS en metros

  Deteccion({
    this.id,
    required this.idMazorca,
    this.grupoImagen,
    required this.idUsuario,
    this.workerId,
    required this.fase,
    required this.confianza,
    required this.severidad,
    required this.colorSemaforo,
    required this.rutaImagen,
    required this.fecha,
    required this.latitud,
    required this.longitud,
    this.direccion,
    this.lote,
    this.notas,
    this.sincronizado = false,
    this.loteId,
    this.enSeguimiento = false,
    this.tratamientoId,
    this.precisionGPS,
  });

  Deteccion copyWith({
    int? id,
    String? idMazorca,
    String? grupoImagen,
    String? idUsuario,
    String? workerId,
    String? fase,
    double? confianza,
    int? severidad,
    String? colorSemaforo,
    String? rutaImagen,
    DateTime? fecha,
    double? latitud,
    double? longitud,
    String? direccion,
    String? lote,
    String? notas,
    bool? sincronizado,
    String? loteId,
    bool? enSeguimiento,
    String? tratamientoId,
    double? precisionGPS,
  }) {
    return Deteccion(
      id: id ?? this.id,
      idMazorca: idMazorca ?? this.idMazorca,
      grupoImagen: grupoImagen ?? this.grupoImagen,
      idUsuario: idUsuario ?? this.idUsuario,
      workerId: workerId ?? this.workerId,
      fase: fase ?? this.fase,
      confianza: confianza ?? this.confianza,
      severidad: severidad ?? this.severidad,
      colorSemaforo: colorSemaforo ?? this.colorSemaforo,
      rutaImagen: rutaImagen ?? this.rutaImagen,
      fecha: fecha ?? this.fecha,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      direccion: direccion ?? this.direccion,
      lote: lote ?? this.lote,
      notas: notas ?? this.notas,
      sincronizado: sincronizado ?? this.sincronizado,
      loteId: loteId ?? this.loteId,
      enSeguimiento: enSeguimiento ?? this.enSeguimiento,
      tratamientoId: tratamientoId ?? this.tratamientoId,
      precisionGPS: precisionGPS ?? this.precisionGPS,
    );
  }

  /// Convertir a Map para SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'idMazorca': idMazorca,
      'grupoImagen': grupoImagen,
      'idUsuario': idUsuario,
      'workerId': workerId,
      'fase': fase, // ✅ Se guarda tal cual: 'SANA', 'FASE_INICIAL', etc.
      'confianza': confianza,
      'severidad': severidad,
      'colorSemaforo': colorSemaforo,
      'rutaImagen': rutaImagen,
      'fecha': fecha.toIso8601String(),
      'latitud': latitud,
      'longitud': longitud,
      'direccion': direccion,
      'lote': lote,
      'notas': notas,
      'sincronizado': sincronizado ? 1 : 0,
      'loteId': loteId,
      'enSeguimiento': enSeguimiento ? 1 : 0,
      'tratamientoId': tratamientoId,
      'precisionGPS': precisionGPS,
    };
  }

  /// Crear desde Map de SQLite
  factory Deteccion.fromMap(Map<String, dynamic> map) {
    return Deteccion(
      id: map['id'] as int?,
      idMazorca: map['idMazorca'] as String,
      grupoImagen: map['grupoImagen'] as String?,
      idUsuario: map['idUsuario'] as String,
      workerId: map['workerId'] as String?,
      fase: map['fase'] as String, // ✅ Se lee tal cual
      confianza: (map['confianza'] as num).toDouble(),
      severidad: map['severidad'] as int,
      colorSemaforo: map['colorSemaforo'] as String,
      rutaImagen: map['rutaImagen'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      latitud: (map['latitud'] as num).toDouble(),
      longitud: (map['longitud'] as num).toDouble(),
      direccion: map['direccion'] as String?,
      lote: map['lote'] as String?,
      notas: map['notas'] as String?,
      sincronizado: (map['sincronizado'] as int) == 1,
      loteId: map['loteId'] as String?,
      enSeguimiento: (map['enSeguimiento'] as int? ?? 0) == 1,
      tratamientoId: map['tratamientoId'] as String?,
      precisionGPS: (map['precisionGPS'] as num?)?.toDouble(),
    );
  }

  // Alias para compatibilidad
  static Deteccion desdeMap(Map<String, dynamic> map) => Deteccion.fromMap(map);

  @override
  String toString() {
    return 'Deteccion(id: $id, fase: $fase, severidad: $severidad, '
        'confianza: ${(confianza * 100).toStringAsFixed(1)}%, '
        'sincronizado: $sincronizado)';
  }
}

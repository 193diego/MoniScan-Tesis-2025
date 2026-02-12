// lib/datos/modelos/deteccion.dart
class Deteccion {
  final int? id;
  final String idMazorca;
  final String? grupoImagen;
  final String idUsuario;
  final String? workerId;
  final String fase;
  final double confianza;
  final int severidad;
  final String colorSemaforo;
  final String rutaImagen;
  final DateTime fecha;
  final double latitud;
  final double longitud;
  final String? direccion;
  final String? lote;
  final String? notas;
  final bool sincronizado;

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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'idMazorca': idMazorca,
      'grupoImagen': grupoImagen,
      'idUsuario': idUsuario,
      'workerId': workerId,
      'fase': fase,
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
    };
  }

  factory Deteccion.fromMap(Map<String, dynamic> map) {
    return Deteccion(
      id: map['id'] as int?,
      idMazorca: map['idMazorca'] as String,
      grupoImagen: map['grupoImagen'] as String?,
      idUsuario: map['idUsuario'] as String,
      workerId: map['workerId'] as String?,
      fase: map['fase'] as String,
      confianza: map['confianza'] as double,
      severidad: map['severidad'] as int,
      colorSemaforo: map['colorSemaforo'] as String,
      rutaImagen: map['rutaImagen'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      latitud: map['latitud'] as double,
      longitud: map['longitud'] as double,
      direccion: map['direccion'] as String?,
      lote: map['lote'] as String?,
      notas: map['notas'] as String?,
      sincronizado: (map['sincronizado'] as int) == 1,
    );
  }
}

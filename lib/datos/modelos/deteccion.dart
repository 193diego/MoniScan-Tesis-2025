// lib/datos/modelos/deteccion.dart
import '../../config/constantes.dart';

/// Modelo de datos para una Detección de Moniliasis
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
  final double latitud;
  final double longitud;
  final String? direccion;
  final String? lote;
  final String? notas;
  final DateTime fecha;
  final bool sincronizado;

  Deteccion({
    this.id,
    required this.idMazorca,
    this.grupoImagen,
    required this.idUsuario,
    this.workerId,
    required this.fase,
    required this.confianza,
    int? severidad,
    String? colorSemaforo,
    required this.rutaImagen,
    required this.latitud,
    required this.longitud,
    this.direccion,
    this.lote,
    this.notas,
    DateTime? fecha,
    this.sincronizado = false,
  }) : fecha = fecha ?? DateTime.now(),
       severidad = severidad ?? Constantes.obtenerSeveridadPorClase(fase),
       colorSemaforo =
           colorSemaforo ??
           Constantes.obtenerColorSemaforo(
             severidad ?? Constantes.obtenerSeveridadPorClase(fase),
           );

  String get confianzaPorcentaje => '${(confianza * 100).toStringAsFixed(1)}%';
  bool get esReciente => DateTime.now().difference(fecha).inHours < 24;
  int get colorFase => Constantes.obtenerColorPorClase(fase);
  String get textoUrgencia => Constantes.obtenerTextoUrgencia(severidad);
  String get nombreClaseDescriptivo => Constantes.obtenerNombreClase(fase);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'id_mazorca': idMazorca,
      'grupo_imagen': grupoImagen,
      'id_usuario': idUsuario,
      'worker_id': workerId,
      'fase': fase,
      'confianza': confianza,
      'severidad': severidad,
      'color_semaforo': colorSemaforo,
      'ruta_imagen': rutaImagen,
      'latitud': latitud,
      'longitud': longitud,
      'direccion': direccion,
      'lote': lote,
      'notas': notas,
      'fecha': fecha.toIso8601String(),
      'sincronizado': sincronizado ? 1 : 0,
    };
  }

  factory Deteccion.desdeMap(Map<String, dynamic> map) {
    return Deteccion(
      id: map['id'] as int?,
      idMazorca: map['id_mazorca'] as String,
      grupoImagen: map['grupo_imagen'] as String?,
      idUsuario: map['id_usuario'] as String,
      workerId: map['worker_id'] as String?,
      fase: map['fase'] as String,
      confianza: map['confianza'] as double,
      severidad: map['severidad'] as int?,
      colorSemaforo: map['color_semaforo'] as String?,
      rutaImagen: map['ruta_imagen'] as String,
      latitud: map['latitud'] as double,
      longitud: map['longitud'] as double,
      direccion: map['direccion'] as String?,
      lote: map['lote'] as String?,
      notas: map['notas'] as String?,
      fecha: DateTime.parse(map['fecha'] as String),
      sincronizado: (map['sincronizado'] as int) == 1,
    );
  }

  Map<String, dynamic> aMapFirebase() {
    return {
      'idMazorca': idMazorca,
      'grupoImagen': grupoImagen,
      'idUsuario': idUsuario,
      'workerId': workerId,
      'workerCedula': idUsuario,
      'fase': fase,
      'confianza': confianza,
      'severidad': severidad,
      'colorSemaforo': colorSemaforo,
      'latitud': latitud,
      'longitud': longitud,
      'direccion': direccion,
      'lote': lote,
      'notas': notas,
      'fecha': fecha.toIso8601String(),
    };
  }

  Deteccion copiarCon({
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
    double? latitud,
    double? longitud,
    String? direccion,
    String? lote,
    String? notas,
    DateTime? fecha,
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
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      direccion: direccion ?? this.direccion,
      lote: lote ?? this.lote,
      notas: notas ?? this.notas,
      fecha: fecha ?? this.fecha,
      sincronizado: sincronizado ?? this.sincronizado,
    );
  }

  @override
  String toString() {
    return 'Deteccion{id: $id, idMazorca: $idMazorca, fase: $fase, '
        'confianza: $confianzaPorcentaje, severidad: $severidad, '
        'semaforo: $colorSemaforo, lote: $lote}';
  }
}

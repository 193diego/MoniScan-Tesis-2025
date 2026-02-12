// lib/datos/modelos/usuario.dart

/// Modelo de datos para el Usuario/Trabajador Agrícola
class Usuario {
  final int? id;
  final String cedula;
  final String nombres;
  final String apellidos;
  final String correo;
  final String? telefono;
  final String? direccion;
  final String? rol;
  final String? rutaFoto;
  final DateTime fechaRegistro;
  final DateTime? fechaActualizacion;

  Usuario({
    this.id,
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    required this.correo,
    this.telefono,
    this.direccion,
    this.rol,
    this.rutaFoto,
    DateTime? fechaRegistro,
    this.fechaActualizacion,
  }) : fechaRegistro = fechaRegistro ?? DateTime.now();

  /// Obtener el nombre completo del usuario
  String get nombreCompleto => '$nombres $apellidos';

  /// Convertir desde Map (SQLite)
  factory Usuario.desdeMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] as int?,
      cedula: map['cedula'] as String,
      nombres: map['nombres'] as String,
      apellidos: map['apellidos'] as String,
      correo: map['correo'] as String,
      telefono: map['telefono'] as String?,
      direccion: map['direccion'] as String?,
      rol: map['rol'] as String?,
      rutaFoto: map['ruta_foto'] as String?,
      fechaRegistro: DateTime.parse(map['fecha_registro'] as String),
      fechaActualizacion: map['fecha_actualizacion'] != null
          ? DateTime.parse(map['fecha_actualizacion'] as String)
          : null,
    );
  }

  /// Convertir a Map (SQLite)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cedula': cedula,
      'nombres': nombres,
      'apellidos': apellidos,
      'correo': correo,
      'telefono': telefono,
      'direccion': direccion,
      'rol': rol,
      'ruta_foto': rutaFoto,
      'fecha_registro': fechaRegistro.toIso8601String(),
      'fecha_actualizacion': fechaActualizacion?.toIso8601String(),
    };
  }

  /// Copiar con modificaciones
  Usuario copiarCon({
    int? id,
    String? cedula,
    String? nombres,
    String? apellidos,
    String? correo,
    String? telefono,
    String? direccion,
    String? rol,
    String? rutaFoto,
    DateTime? fechaRegistro,
    DateTime? fechaActualizacion,
  }) {
    return Usuario(
      id: id ?? this.id,
      cedula: cedula ?? this.cedula,
      nombres: nombres ?? this.nombres,
      apellidos: apellidos ?? this.apellidos,
      correo: correo ?? this.correo,
      telefono: telefono ?? this.telefono,
      direccion: direccion ?? this.direccion,
      rol: rol ?? this.rol,
      rutaFoto: rutaFoto ?? this.rutaFoto,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
    );
  }

  @override
  String toString() {
    return 'Usuario{id: $id, cedula: $cedula, nombreCompleto: $nombreCompleto, correo: $correo}';
  }
}

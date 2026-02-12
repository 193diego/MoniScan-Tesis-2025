// lib/config/constantes.dart
/// Constantes globales del sistema
class Constantes {
  // ==================== APLICACIÓN ====================
  static const String nombreApp = 'MoniScan';

  // ==================== BASE DE DATOS ====================
  static const String nombreBaseDatos = 'moniscan.db';
  static const String tablaUsuarios = 'usuarios';
  static const String tablaDetecciones = 'detecciones';

  // ==================== MODELO DE IA ====================
  static const String rutaModelo = 'assets/models/best_float32.tflite';
  static const String rutaLabels = 'assets/models/labels.txt';
  static const int tamanoEntradaModelo = 640;
  static const int numeroClases = 4; // 4 clases
  static const int numeroMaximoDetecciones = 100;
  static const double umbralConfianza = 0.5;
  static const double umbralIoU = 0.45;

  // ==================== CLASES DE MONILIASIS (ACTUALIZADAS) ====================
  static const List<String> nombresClases = [
    'FASE_AVANZADA',
    'FASE_INICIAL',
    'FASE_INTERMEDIA',
    'SANA',
  ];

  // ==================== MAPEO DE SEVERIDAD ====================
  static int obtenerSeveridadPorClase(String nombreClase) {
    switch (nombreClase) {
      case 'SANA':
        return 0;
      case 'FASE_INICIAL':
        return 1;
      case 'FASE_INTERMEDIA':
        return 2;
      case 'FASE_AVANZADA':
        return 3;
      default:
        return 0;
    }
  }

  static String obtenerColorSemaforo(int severidad) {
    switch (severidad) {
      case 0:
        return 'verde';
      case 1:
        return 'amarillo';
      case 2:
        return 'naranja';
      case 3:
        return 'rojo';
      default:
        return 'verde';
    }
  }

  static int obtenerColorPorClase(String nombreClase) {
    final severidad = obtenerSeveridadPorClase(nombreClase);
    switch (severidad) {
      case 0:
        return 0xFF4CAF50; // Verde
      case 1:
        return 0xFFFFC107; // Amarillo
      case 2:
        return 0xFFFF9800; // Naranja
      case 3:
        return 0xFFF44336; // Rojo
      default:
        return 0xFF9E9E9E; // Gris
    }
  }

  static String obtenerNombreClase(String nombreClase) {
    switch (nombreClase) {
      case 'SANA':
        return 'Mazorca Sana';
      case 'FASE_INICIAL':
        return 'Moniliasis Inicial';
      case 'FASE_INTERMEDIA':
        return 'Moniliasis Intermedia';
      case 'FASE_AVANZADA':
        return 'Moniliasis Avanzada';
      default:
        return nombreClase;
    }
  }

  static String obtenerTextoUrgencia(int severidad) {
    switch (severidad) {
      case 0:
        return 'Sin acción requerida';
      case 1:
        return 'Monitoreo recomendado';
      case 2:
        return 'Acción sugerida';
      case 3:
        return 'Acción prioritaria';
      default:
        return 'Sin clasificar';
    }
  }

  // ==================== GPS Y UBICACIÓN ====================
  static const double precisionGPS = 10.0;
  static const double latitudPorDefecto = -2.1894;
  static const double longitudPorDefecto = -79.8892;

  // ==================== FIREBASE ====================
  static const String coleccionUsuarios = 'workers';
  static const String coleccionDetecciones = 'detecciones';
  static const String coleccionRecomendaciones = 'recomendaciones';

  // ==================== VALIDACIONES ====================
  static const int longitudMinimaCedula = 10;
  static const int longitudMaximaCedula = 10;

  static bool validarCedula(String cedula) {
    if (cedula.length != longitudMinimaCedula) return false;
    return RegExp(r'^\d+$').hasMatch(cedula);
  }

  static bool validarEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // ==================== FORMATO DE FECHAS ====================
  static String formatearFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  static String formatearFechaHora(DateTime fecha) {
    return '${formatearFecha(fecha)} ${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
  }
}

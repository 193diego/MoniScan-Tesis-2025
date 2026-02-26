// lib/config/constantes.dart
// ✅ VERSIÓN CORREGIDA - MoniScan - La Finca
// CAMBIO: colorSemaforo de FASE_INTERMEDIA era "naranja", ahora es "amarillo"
// para coincidir con el diccionario de datos (solo acepta: verde, amarillo, rojo)
import 'package:flutter/material.dart';

class Constantes {
  // ✅ BRANDING
  static const String nombreApp = 'MoniScan';
  static const String nombreEmpresa = 'La Finca';
  static const String nombreCompleto = 'MoniScan - La Finca';
  static const String versionApp = '1.0.0';

  // FIREBASE
  static const String coleccionUsuarios = 'usuarios';
  static const String coleccionDetecciones = 'detecciones';
  static const String coleccionSeguimientos = 'seguimientos';
  static const String coleccionTratamientos = 'tratamientos';
  static const String coleccionLotes = 'lotes';
  static const String carpetaImagenesDetecciones = 'imagenes/detecciones';
  static const String carpetaImagenesSeguimientos = 'imagenes/seguimientos';
  static const String carpetaFotosPerfil = 'fotos_perfil';

  // SQLITE
  static const String nombreBaseDatos = 'moniscan.db';
  static const int versionBaseDatos = 6;
  static const String tablaUsuarios = 'usuarios';
  static const String tablaDetecciones = 'detecciones';

  // ═══════════════════════════════════════════════════════
  // MODELOS IA
  // ═══════════════════════════════════════════════════════
  static const String rutaModelo = 'assets/models/best_640_float16.tflite';
  static const String rutaModeloYolo = 'assets/models/best_320_int8.tflite';

  static const int tamanoEntradaModelo = 640;
  static const int tamanoEntradaModeloYolo = 320;

  static const int numeroClases = 4;
  static const int numeroMaximoDetecciones = 100;
  static const double umbralConfianza = 0.40;
  static const double umbralIoU = 0.45;

  // ✅ ETIQUETAS YOLO — orden exacto según modelo exportado
  // {0:'FASE_AVANZADA', 1:'FASE_INICIAL', 2:'FASE_INTERMEDIA', 3:'SANA'}
  static const List<String> nombresClases = [
    'FASE_AVANZADA', // índice 0
    'FASE_INICIAL', // índice 1
    'FASE_INTERMEDIA', // índice 2
    'SANA', // índice 3
  ];

  // GPS POR DEFECTO (Guayaquil, Ecuador)
  static const double latitudPorDefecto = -2.1709979;
  static const double longitudPorDefecto = -79.9223592;
  static const double latitudMinEcuador = -5.02;
  static const double latitudMaxEcuador = 1.45;
  static const double longitudMinEcuador = -81.08;
  static const double longitudMaxEcuador = -75.19;

  // ═══════════════════════════════════════════════════════════════
  // MÉTODOS DE CONVERSIÓN Y HELPERS
  // ═══════════════════════════════════════════════════════════════

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

  // ✅ CORREGIDO: El diccionario solo acepta "verde", "amarillo", "rojo"
  // FASE_INTERMEDIA usaba "naranja" — ahora usa "amarillo"
  static String obtenerColorSemaforo(int severidad) {
    switch (severidad) {
      case 0:
        return 'verde';
      case 1:
        return 'amarillo';
      case 2:
        return 'amarillo'; // ← CORREGIDO: era "naranja", no existe en el diccionario
      case 3:
        return 'rojo';
      default:
        return 'verde';
    }
  }

  static String obtenerNombreClase(int indice) {
    if (indice >= 0 && indice < nombresClases.length) {
      return nombresClases[indice];
    }
    return 'SANA';
  }

  static String obtenerNombreLegible(String nombreClase) {
    switch (nombreClase) {
      case 'SANA':
        return 'Sana';
      case 'FASE_INICIAL':
        return 'Fase Inicial';
      case 'FASE_INTERMEDIA':
        return 'Fase Intermedia';
      case 'FASE_AVANZADA':
        return 'Fase Avanzada';
      default:
        return nombreClase;
    }
  }

  static Color obtenerColorPorClase(String nombreClase) {
    final severidad = obtenerSeveridadPorClase(nombreClase);
    switch (severidad) {
      case 0:
        return const Color(0xFF4CAF50);
      case 1:
        return const Color(0xFFFFC107);
      case 2:
        return const Color(0xFFFF9800);
      case 3:
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  static int obtenerColorIntPorClase(String nombreClase) {
    final color = obtenerColorPorClase(nombreClase);
    return ((color.a * 255.0).round().clamp(0, 255) << 24) |
        ((color.r * 255.0).round().clamp(0, 255) << 16) |
        ((color.g * 255.0).round().clamp(0, 255) << 8) |
        (color.b * 255.0).round().clamp(0, 255);
  }

  static String obtenerNombreClaseDesdeUI(String nombreUI) {
    switch (nombreUI) {
      case 'Sana':
        return 'SANA';
      case 'Fase Inicial':
        return 'FASE_INICIAL';
      case 'Fase Intermedia':
        return 'FASE_INTERMEDIA';
      case 'Fase Avanzada':
        return 'FASE_AVANZADA';
      default:
        return nombreUI;
    }
  }

  static int obtenerNumeroFaseFirestore(String nombreClase) =>
      obtenerSeveridadPorClase(nombreClase);

  static String obtenerNombreClaseDesdeNumero(int numeroFase) {
    switch (numeroFase) {
      case 0:
        return 'SANA';
      case 1:
        return 'FASE_INICIAL';
      case 2:
        return 'FASE_INTERMEDIA';
      case 3:
        return 'FASE_AVANZADA';
      default:
        return 'SANA';
    }
  }

  static bool esClaseValida(String nombreClase) =>
      nombresClases.contains(nombreClase);
  static bool esSeveridadValida(int severidad) =>
      severidad >= 0 && severidad <= 3;

  static bool coordenadasEnEcuador(double latitud, double longitud) {
    return latitud >= latitudMinEcuador &&
        latitud <= latitudMaxEcuador &&
        longitud >= longitudMinEcuador &&
        longitud <= longitudMaxEcuador;
  }

  static IconData obtenerIconoPorSeveridad(int severidad) {
    switch (severidad) {
      case 0:
        return Icons.check_circle;
      case 1:
        return Icons.warning_amber;
      case 2:
        return Icons.error_outline;
      case 3:
        return Icons.dangerous;
      default:
        return Icons.help_outline;
    }
  }

  static String obtenerMensajeUrgencia(int severidad) {
    switch (severidad) {
      case 0:
        return 'Sin urgencia - Mazorca sana';
      case 1:
        return 'Urgencia baja - Monitorear';
      case 2:
        return 'Urgencia media - Aplicar tratamiento';
      case 3:
        return 'Urgencia alta - Acción inmediata requerida';
      default:
        return '';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CONFIGURACIÓN GENERAL
  // ═══════════════════════════════════════════════════════════════

  static const Duration intervaloSincronizacion = Duration(minutes: 15);
  static const int loteMaximoSincronizacion = 50;
  static const Duration timeoutFirestore = Duration(seconds: 30);
  static const int maxImagenesCacheadas = 100;
  static const Duration duracionCacheImagenes = Duration(days: 7);

  // MAPA
  static const double zoomInicialMapa = 15.0;
  static const double zoomMaximoMapa = 20.0;
  static const double zoomMinimoMapa = 10.0;

  // NOTIFICACIONES
  static const String canalNotificacionesId = 'moniscan_sync';
  static const String canalNotificacionesNombre = 'Sincronización MoniScan';
  static const String canalNotificacionesDesc =
      'Notificaciones de sincronización con Firebase';

  // MENSAJES
  static const String mensajeErrorConexion =
      'No hay conexión a internet. Trabajando en modo offline.';
  static const String mensajeSincronizandoFirebase =
      'Sincronizando con Firebase...';
  static const String mensajeSincronizacionExitosa =
      'Sincronización completada exitosamente';
  static const String mensajeErrorSincronizacion =
      'Error al sincronizar. Se reintentará automáticamente.';
  static const String mensajeGuardadoLocal =
      'Detección guardada localmente. Se subirá cuando haya conexión.';

  // DESARROLLO
  static const bool modoDebug = true;
  static const bool usarEmuladorFirebase = false;
  static const int maxReintentos = 3;
  static const Duration tiempoEntreReintentos = Duration(seconds: 2);
  static const Duration timeoutConexion = Duration(seconds: 10);

  // FORMATEO DE FECHAS
  static const String formatoFechaCorta = 'dd/MM/yyyy';
  static const String formatoFechaLarga = 'dd/MM/yyyy HH:mm';
  static const String formatoHora = 'HH:mm';
  static const String formatoFechaCompleta = 'EEEE, dd MMMM yyyy';

  // LÍMITES
  static const int maxCaracteresNotas = 500;
  static const int maxCaracteresNombreLote = 50;
  static const int maxCaracteresNumeroArbol = 20;
  static const int longitudCedula = 10;

  // COLORES PRINCIPALES
  static const Color colorPrimario = Color(0xFF1B5E20);
  static const Color colorSecundario = Color(0xFF4CAF50);
  static const Color colorFondo = Color(0xFFF5F5F5);
  static const Color colorTexto = Color(0xFF212121);
  static const Color colorTextoSecundario = Color(0xFF757575);

  // COLORES POR FASE
  static const Color colorSana = Color(0xFF4CAF50);
  static const Color colorFaseInicial = Color(0xFFFFC107);
  static const Color colorFaseIntermedia = Color(0xFFFF9800);
  static const Color colorFaseAvanzada = Color(0xFFF44336);

  // CÁMARA E IMÁGENES
  static const double calidadImagenJPEG = 0.85;
  static const int anchoMaximoImagen = 1920;
  static const int altoMaximoImagen = 1080;
}

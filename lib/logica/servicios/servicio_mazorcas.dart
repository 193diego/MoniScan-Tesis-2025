import 'dart:math' show sin, cos, sqrt, asin;
import 'package:flutter/foundation.dart'; // ✅ AGREGADO para debugPrint
import 'package:uuid/uuid.dart';
import '../../datos/local/base_datos_helper.dart';

/// Servicio para gestión inteligente de IDs de mazorcas
class ServicioMazorcas {
  final BaseDatosHelper _db = BaseDatosHelper();
  final Uuid _uuid = const Uuid();

  /// Generar ID único para una nueva mazorca
  String generarIdNuevo() {
    return _uuid.v4();
  }

  /// Buscar mazorca cercana (mismo lote y coordenadas cercanas)
  ///
  /// FUNDAMENTO ACADÉMICO:
  /// - El GPS en dispositivos móviles de uso agrícola presenta
  ///   un error típico de entre 3 y 10 metros.
  /// - En condiciones de campo (follaje denso, humedad, nubosidad)
  ///   el error puede incrementarse significativamente.
  /// - Una mazorca física NO se desplaza, pero sus lecturas GPS sí varían.
  ///
  /// ENFOQUE IMPLEMENTADO:
  /// - El primer escaneo establece un punto de referencia canónico.
  /// - Escaneos posteriores se asocian si:
  ///   a) Están dentro de un radio de tolerancia (por defecto 5 metros).
  ///   b) Corresponden al mismo lote (si el lote fue especificado).
  /// - Se reutiliza el ID único de la mazorca original.
  ///
  /// JUSTIFICACIÓN DEL RADIO:
  /// - 5 metros es un valor óptimo en plantaciones agrícolas:
  ///   • Compensa el error GPS típico.
  ///   • Reduce falsos positivos entre plantas cercanas.
  ///   • Es coherente con prácticas de agricultura de precisión.
  ///
  /// @param radioMetros Radio de tolerancia espacial (5m por defecto)
  Future<String?> buscarMazorcaCercana({
    required String idUsuario,
    required double latitud,
    required double longitud,
    String? lote,
    double radioMetros = 5.0, // 5m compensa error GPS típico
  }) async {
    try {
      final detecciones = await _db.obtenerTodasDetecciones(idUsuario);
      if (detecciones.isEmpty) return null;

      var candidatas = detecciones;
      if (lote != null && lote.isNotEmpty) {
        candidatas = detecciones.where((d) => d.lote == lote).toList();
      }

      String? mazorcaCercana;
      double distanciaMinima = double.infinity;

      for (var deteccion in candidatas) {
        final distancia = _calcularDistancia(
          latitud,
          longitud,
          deteccion.latitud,
          deteccion.longitud,
        );

        if (distancia <= radioMetros && distancia < distanciaMinima) {
          distanciaMinima = distancia;
          mazorcaCercana = deteccion.idMazorca;
        }
      }

      if (mazorcaCercana != null) {
        debugPrint(
          '✅ Mazorca cercana encontrada a ${distanciaMinima.toStringAsFixed(2)}m',
        );
      }

      return mazorcaCercana;
    } catch (e) {
      debugPrint('❌ Error buscando mazorca cercana: $e');
      return null;
    }
  }

  /// Calcular distancia entre dos coordenadas (Fórmula de Haversine)
  double _calcularDistancia(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0; // Radio de la Tierra en metros
    final dLat = _gradosARadianes(lat2 - lat1);
    final dLon = _gradosARadianes(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_gradosARadianes(lat1)) *
            cos(_gradosARadianes(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * asin(sqrt(a));
    return R * c;
  }

  double _gradosARadianes(double grados) {
    return grados * (3.141592653589793 / 180.0);
  }

  /// Obtener sugerencia de ID de mazorca (nueva o seguimiento)
  Future<Map<String, dynamic>> obtenerSugerenciaId({
    required String idUsuario,
    required double latitud,
    required double longitud,
    String? lote,
  }) async {
    final mazorcaCercana = await buscarMazorcaCercana(
      idUsuario: idUsuario,
      latitud: latitud,
      longitud: longitud,
      lote: lote,
    );

    if (mazorcaCercana != null) {
      return {
        'tipo': 'seguimiento',
        'idMazorca': mazorcaCercana,
        'mensaje': 'Mazorca detectada previamente en esta ubicación',
      };
    } else {
      return {
        'tipo': 'nueva',
        'idMazorca': generarIdNuevo(),
        'mensaje': 'Nueva mazorca detectada',
      };
    }
  }
}

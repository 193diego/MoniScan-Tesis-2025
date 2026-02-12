import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../config/constantes.dart';

/// Servicio para gestionar la geolocalización y permisos GPS
class ServicioGPS {
  /// Verificar si los servicios de ubicación están habilitados
  Future<bool> serviciosHabilitados() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Verificar y solicitar permisos de ubicación
  Future<bool> verificarPermisos() async {
    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        return false;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Obtener la ubicación actual del dispositivo
  Future<Position?> obtenerUbicacionActual() async {
    try {
      // Verificar servicios
      final serviciosActivos = await serviciosHabilitados();
      if (!serviciosActivos) {
        throw Exception('Los servicios de ubicación están deshabilitados');
      }

      // Verificar permisos
      final tienePermisos = await verificarPermisos();
      if (!tienePermisos) {
        throw Exception('No se otorgaron permisos de ubicación');
      }

      // Obtener ubicación con precisión alta (COMPATIBLE geolocator ^12)
      final posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return posicion;
    } catch (e) {
      print('Error al obtener ubicación: $e');
      return null;
    }
  }

  /// Obtener coordenadas con valores por defecto si falla
  Future<Map<String, double>> obtenerCoordenadas() async {
    final posicion = await obtenerUbicacionActual();

    if (posicion != null) {
      return {'latitud': posicion.latitude, 'longitud': posicion.longitude};
    }

    // Coordenadas por defecto (Guayaquil, Ecuador)
    return {
      'latitud': Constantes.latitudPorDefecto,
      'longitud': Constantes.longitudPorDefecto,
    };
  }

  /// Obtener la dirección a partir de coordenadas (geocodificación inversa)
  Future<String?> obtenerDireccion(double latitud, double longitud) async {
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        latitud,
        longitud,
      );

      if (placemarks.isEmpty) return null;

      final lugar = placemarks.first;
      final partesDireccion = [
        lugar.street,
        lugar.locality,
        lugar.administrativeArea,
        lugar.country,
      ].where((parte) => parte != null && parte.isNotEmpty);

      return partesDireccion.join(', ');
    } catch (e) {
      print('Error al obtener dirección: $e');
      return null;
    }
  }

  /// Calcular la distancia entre dos puntos en metros
  double calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Formatear coordenadas para mostrar al usuario
  String formatearCoordenadas(double latitud, double longitud) {
    final latFormatted = latitud.toStringAsFixed(6);
    final lonFormatted = longitud.toStringAsFixed(6);
    return '$latFormatted, $lonFormatted';
  }

  /// Abrir la configuración de ubicación del dispositivo
  Future<bool> abrirConfiguracion() async {
    return await Geolocator.openLocationSettings();
  }
}

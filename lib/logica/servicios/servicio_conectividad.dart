import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Servicio para gestionar conectividad y sincronización automática
class ServicioConectividad {
  static final ServicioConectividad _instancia =
      ServicioConectividad._interno();
  factory ServicioConectividad() => _instancia;
  ServicioConectividad._interno();

  final Connectivity _connectivity = Connectivity();
  final _controladorEstado = StreamController<bool>.broadcast();

  bool _tieneConexion = false;
  StreamSubscription? _suscripcion;

  /// Stream del estado de conectividad
  Stream<bool> get estadoConexion => _controladorEstado.stream;

  /// Estado actual de conexión
  bool get tieneConexion => _tieneConexion;

  /// Inicializar monitoreo de conectividad
  Future<void> inicializar() async {
    try {
      // Verificar estado inicial
      _tieneConexion = await _verificarConexion();
      _controladorEstado.add(_tieneConexion);

      // Escuchar cambios
      _suscripcion = _connectivity.onConnectivityChanged.listen((result) async {
        final tieneConexionAhora = await _verificarConexion();

        if (tieneConexionAhora != _tieneConexion) {
          _tieneConexion = tieneConexionAhora;
          _controladorEstado.add(_tieneConexion);

          debugPrint(
            _tieneConexion
                ? '✅ Conexión a internet restaurada'
                : '❌ Conexión a internet perdida',
          );
        }
      });
    } catch (e) {
      debugPrint('❌ Error inicializando conectividad: $e');
    }
  }

  /// Verificar si hay conexión real
  Future<bool> _verificarConexion() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('❌ Error verificando conectividad: $e');
      return false;
    }
  }

  /// Detener monitoreo
  void dispose() {
    _suscripcion?.cancel();
    _controladorEstado.close();
  }
}

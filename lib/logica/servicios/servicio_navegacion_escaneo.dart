// lib/logica/servicios/servicio_navegacion_escaneo.dart
import 'package:flutter/material.dart';
// ✅ CORRECCIÓN: Solo se importa escaneo_screen.dart para EscaneoScreen
import '../../presentacion/pantallas/escaneo_screen.dart';
// ✅ CORRECCIÓN: escaneo_seguimiento_screen.dart es la ÚNICA fuente de EscaneoSeguimientoScreen
// Esto elimina el error "ambiguous_import": EscaneoSeguimientoScreen ya NO existe en escaneo_screen.dart
import '../../presentacion/pantallas/escaneo_seguimiento_screen.dart';

/// Servicio para gestionar navegación unificada hacia pantallas de escaneo
class ServicioNavegacionEscaneo {
  static final ServicioNavegacionEscaneo _instancia =
      ServicioNavegacionEscaneo._interno();
  factory ServicioNavegacionEscaneo() => _instancia;
  ServicioNavegacionEscaneo._interno();

  /// Iniciar escaneo nuevo desde cualquier punto
  ///
  /// Usado desde:
  /// - Pantalla de inicio
  /// - Botón flotante en mapa
  /// - Acción rápida en historial
  Future<void> iniciarEscaneoNuevo({
    required BuildContext context,
    required String cedulaUsuario,
    double? latitudSugerida,
    double? longitudSugerida,
  }) async {
    // ✅ CORRECCIÓN: EscaneoScreen es un StatefulWidget, se navega con builder
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EscaneoScreen(
          usuarioId: cedulaUsuario,
          onVolverInicio: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// Continuar seguimiento de mazorca existente
  ///
  /// Usado desde:
  /// - Detalle de seguimiento
  /// - Selección en mapa
  /// - Elemento del historial
  Future<bool?> continuarSeguimiento({
    required BuildContext context,
    required String cedulaUsuario,
    required String idMazorca,
    required String grupoImagen,
    String? seguimientoId,
  }) async {
    // ✅ CORRECCIÓN: EscaneoSeguimientoScreen es un StatefulWidget, se navega con builder
    return await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EscaneoSeguimientoScreen(
          cedulaUsuario: cedulaUsuario,
          idMazorca: idMazorca,
          grupoImagen: grupoImagen,
          seguimientoId: seguimientoId,
        ),
      ),
    );
  }

  /// Escanear desde ubicación específica del mapa
  ///
  /// Detecta automáticamente si hay mazorca cercana para continuar seguimiento
  Future<void> escanearDesdeUbicacion({
    required BuildContext context,
    required String cedulaUsuario,
    required double latitud,
    required double longitud,
    String? idMazorcaCercana,
    String? grupoImagen,
    String? seguimientoId,
  }) async {
    if (idMazorcaCercana != null && grupoImagen != null) {
      await continuarSeguimiento(
        context: context,
        cedulaUsuario: cedulaUsuario,
        idMazorca: idMazorcaCercana,
        grupoImagen: grupoImagen,
        seguimientoId: seguimientoId,
      );
    } else {
      await iniciarEscaneoNuevo(
        context: context,
        cedulaUsuario: cedulaUsuario,
        latitudSugerida: latitud,
        longitudSugerida: longitud,
      );
    }
  }
}

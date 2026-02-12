// lib/logica/servicios/servicio_navegacion_escaneo.dart
import 'package:flutter/material.dart';
import '../../presentacion/pantallas/escaneo_screen.dart';
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        // ═══════════════════════════════════════════════════════
        // CORREGIDO: EscaneoScreen NO requiere grupoImagen
        // ═══════════════════════════════════════════════════════
        builder: (_) => EscaneoScreen(
          cedulaUsuario: cedulaUsuario,
          // ✅ Parámetros opcionales (pueden agregarse si se necesitan)
          // idMazorcaSeguimiento: null,
          // grupoImagenSeguimiento: null,
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
  }) async {
    return await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        // ═══════════════════════════════════════════════════════
        // CORREGIDO: Constructor correcto de EscaneoSeguimientoScreen
        // ═══════════════════════════════════════════════════════
        builder: (_) => EscaneoSeguimientoScreen(
          cedulaUsuario: cedulaUsuario,
          idMazorca: idMazorca,
          grupoImagen: grupoImagen,
          // ❌ ELIMINADOS: lote y ultimaFase (no existen en constructor)
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
  }) async {
    if (idMazorcaCercana != null && grupoImagen != null) {
      // Hay mazorca cercana: continuar seguimiento
      await continuarSeguimiento(
        context: context,
        cedulaUsuario: cedulaUsuario,
        idMazorca: idMazorcaCercana,
        grupoImagen: grupoImagen,
      );
    } else {
      // No hay mazorca cercana: nuevo escaneo
      await iniciarEscaneoNuevo(
        context: context,
        cedulaUsuario: cedulaUsuario,
        latitudSugerida: latitud,
        longitudSugerida: longitud,
      );
    }
  }
}

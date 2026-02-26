// lib/utils/manejador_permisos.dart
// ✅ CORRECCIÓN: unintended_html_in_doc_comment fixed
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

/// Manejador de permisos de cámara
class ManejadorPermisos {
  /// Verificar y solicitar permiso de cámara
  ///
  /// Se captura ScaffoldMessengerState y NavigatorState ANTES de cualquier await.
  static Future<bool> solicitarPermisoCamara(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final status = await Permission.camera.status;

      if (status.isGranted) {
        debugPrint('✅ Permiso de cámara ya concedido');
        return true;
      }

      if (status.isPermanentlyDenied) {
        await _mostrarDialogoAjustes(navigator);
        return false;
      }

      debugPrint('📸 Solicitando permiso de cámara...');
      final result = await Permission.camera.request();

      if (result.isGranted) {
        debugPrint('✅ Permiso concedido');
        return true;
      } else if (result.isPermanentlyDenied) {
        await _mostrarDialogoAjustes(navigator);
        return false;
      } else {
        debugPrint('❌ Permiso denegado');
        _mostrarSnackbar(
          scaffoldMessenger,
          'Se necesita permiso de cámara para detectar mazorcas',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error solicitando permiso: $e');
      return false;
    }
  }

  /// Mostrar diálogo para ir a ajustes usando NavigatorState precapturado
  ///
  /// ✅ FIX: Backticks around `<void>` to avoid HTML interpretation in doc comment
  static Future<void> _mostrarDialogoAjustes(NavigatorState navigator) async {
    await navigator.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Permiso requerido'),
          content: const Text(
            'La aplicación necesita acceso a la cámara para funcionar. '
            'Por favor, habilita el permiso en la configuración.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await openAppSettings();
              },
              child: const Text('Ir a Ajustes'),
            ),
          ],
        ),
      ),
    );
  }

  /// Mostrar snackbar usando ScaffoldMessengerState precapturado
  static void _mostrarSnackbar(
    ScaffoldMessengerState messenger,
    String mensaje,
  ) {
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  /// Verificar todos los permisos necesarios
  static Future<Map<String, bool>> verificarPermisos() async {
    final resultados = <String, bool>{};

    resultados['camara'] = await Permission.camera.isGranted;
    resultados['ubicacion'] = await Permission.location.isGranted;
    resultados['almacenamiento'] = await Permission.storage.isGranted;

    debugPrint('📋 Estado de permisos: $resultados');
    return resultados;
  }

  /// Solicitar permiso de ubicación
  static Future<bool> solicitarPermisoUbicacion(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final status = await Permission.location.status;

      if (status.isGranted) return true;

      final result = await Permission.location.request();

      if (result.isGranted) {
        debugPrint('✅ Permiso de ubicación concedido');
        return true;
      } else {
        _mostrarSnackbar(
          scaffoldMessenger,
          'Se recomienda activar la ubicación para registrar dónde se detectó la enfermedad',
        );
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error solicitando permiso de ubicación: $e');
      return false;
    }
  }
}

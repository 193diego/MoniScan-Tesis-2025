import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

/// Manejador global de errores y excepciones
class ManejadorErrores {
  static final ManejadorErrores _instancia = ManejadorErrores._interno();
  factory ManejadorErrores() => _instancia;
  ManejadorErrores._interno();

  /// Inicializar manejador global de errores
  static void inicializar() {
    // Capturar errores de Flutter
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _registrarError(details.exception, details.stack, 'Flutter Error');
    };

    // Capturar errores asíncronos no manejados
    PlatformDispatcher.instance.onError = (error, stack) {
      _registrarError(error, stack, 'Async Error');
      return true;
    };

    // Capturar errores de zona
    runZonedGuarded(
      () {
        // El código de la app se ejecutará aquí
      },
      (error, stack) {
        _registrarError(error, stack, 'Zone Error');
      },
    );
  }

  /// Registrar error en consola y sistema de logging
  static void _registrarError(dynamic error, StackTrace? stack, String tipo) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('❌ ERROR CAPTURADO: $tipo');
    debugPrint('═══════════════════════════════════════');
    debugPrint('Error: $error');
    debugPrint('Stack Trace: $stack');
    debugPrint('═══════════════════════════════════════');

    // TODO: Aquí se puede integrar con Firebase Crashlytics
    // FirebaseCrashlytics.instance.recordError(error, stack);
  }

  /// Ejecutar función con manejo de errores
  static Future<T?> ejecutarSeguro<T>({
    required Future<T> Function() funcion,
    required BuildContext? context,
    String? mensajeError,
    bool mostrarDialogo = false,
  }) async {
    try {
      return await funcion();
    } on TimeoutException catch (e) {
      _manejarError(
        context: context,
        error: 'Tiempo de espera agotado',
        detalles: e.toString(),
        mensajePersonalizado: mensajeError,
        mostrarDialogo: mostrarDialogo,
      );
      return null;
    } on FormatException catch (e) {
      _manejarError(
        context: context,
        error: 'Error de formato de datos',
        detalles: e.toString(),
        mensajePersonalizado: mensajeError,
        mostrarDialogo: mostrarDialogo,
      );
      return null;
    } catch (e, stack) {
      _registrarError(e, stack, 'Execution Error');
      _manejarError(
        context: context,
        error: 'Error inesperado',
        detalles: e.toString(),
        mensajePersonalizado: mensajeError,
        mostrarDialogo: mostrarDialogo,
      );
      return null;
    }
  }

  /// Manejar error mostrando mensaje al usuario
  static void _manejarError({
    required BuildContext? context,
    required String error,
    required String detalles,
    String? mensajePersonalizado,
    bool mostrarDialogo = false,
  }) {
    final mensaje = mensajePersonalizado ?? error;

    if (context != null && context.mounted) {
      if (mostrarDialogo) {
        _mostrarDialogoError(context, mensaje, detalles);
      } else {
        _mostrarSnackbar(context, mensaje);
      }
    }
  }

  /// Mostrar Snackbar de error
  static void _mostrarSnackbar(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  /// Mostrar diálogo de error detallado
  static void _mostrarDialogoError(
    BuildContext context,
    String mensaje,
    String detalles,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mensaje,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              const Text(
                'Detalles técnicos:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  detalles,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

/// Extension para manejo de errores en Future
extension FutureErrorHandling<T> on Future<T> {
  Future<T?> conManejo(BuildContext context, {String? mensajeError}) async {
    return ManejadorErrores.ejecutarSeguro(
      funcion: () => this,
      context: context,
      mensajeError: mensajeError,
    );
  }
}
// lib/presentacion/pantallas/escaneo_seguimiento_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../logica/servicios/servicio_ia.dart';
import '../../logica/servicios/servicio_gps.dart';
import '../../logica/servicios/servicio_sincronizacion.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';
import 'detalle_deteccion_screen.dart';

/// Pantalla de escaneo para seguimiento de mazorca
/// Usa YOLOView para detección en tiempo real (igual que EscaneoScreen)
class EscaneoSeguimientoScreen extends StatefulWidget {
  final String cedulaUsuario;
  final String idMazorca;
  final String grupoImagen;

  const EscaneoSeguimientoScreen({
    super.key,
    required this.cedulaUsuario,
    required this.idMazorca,
    required this.grupoImagen,
  });

  @override
  State<EscaneoSeguimientoScreen> createState() =>
      _EscaneoSeguimientoScreenState();
}

class _EscaneoSeguimientoScreenState extends State<EscaneoSeguimientoScreen> {
  final ServicioIA _servicioIA = ServicioIA();
  final ServicioGPS _servicioGPS = ServicioGPS();
  final BaseDatosHelper _bd = BaseDatosHelper();
  final ServicioSincronizacion _sincronizacion = ServicioSincronizacion();

  bool _inicializado = false;
  bool _procesando = false;

  List<YOLOResult> _detecciones = [];
  double _fps = 0;
  double _latenciaMs = 0;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      await _servicioIA.cargarModelo();
      setState(() => _inicializado = true);
    } catch (e) {
      if (mounted) _mostrarMensaje('Error: $e');
    }
  }

  void _onDeteccionesRecibidas(List<YOLOResult> results) {
    if (_procesando || !mounted) return;
    setState(() => _detecciones = results);
  }

  void _onMetricasRendimiento(YOLOPerformanceMetrics metrics) {
    if (!mounted) return;
    setState(() {
      _fps = metrics.fps;
      _latenciaMs = metrics.processingTimeMs;
    });
  }

  Future<void> _capturarYGuardar() async {
    if (_detecciones.isEmpty) {
      _mostrarMensaje('No hay detecciones');
      return;
    }
    if (_procesando) return;

    setState(() => _procesando = true);

    try {
      _mostrarDialogoCarga('Procesando...');

      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempFile = File(tempPath);

      // TODO: Implementar captura real del frame de YOLOView
      // Por ahora creamos un archivo vacío
      await tempFile.writeAsBytes([]);

      if (!mounted) return;
      Navigator.of(context).pop();

      _mostrarDialogoCarga('Dibujando anotaciones...');

      final imagenAnotada = await _servicioIA.dibujarAnotacionesEnImagen(
        imagenOriginal: tempFile,
        detecciones: _detecciones,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      _mostrarDialogoCarga('Obteniendo ubicación...');

      final coordenadas = await _servicioGPS.obtenerCoordenadas();
      final direccion = await _servicioGPS.obtenerDireccion(
        coordenadas['latitud']!,
        coordenadas['longitud']!,
      );

      final directorioApp = await getApplicationDocumentsDirectory();
      final nombreArchivo =
          'seguimiento_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final rutaDestino = '${directorioApp.path}/$nombreArchivo';
      await imagenAnotada.copy(rutaDestino);

      if (!mounted) return;
      Navigator.of(context).pop();

      await _guardarDetecciones(File(rutaDestino), coordenadas, direccion);

      try {
        await tempFile.delete();
      } catch (e) {
        debugPrint('⚠️ Error limpiando: $e');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _mostrarMensaje('Error: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _guardarDetecciones(
    File imagenFile,
    Map<String, double> coordenadas,
    String? direccion,
  ) async {
    _mostrarDialogoCarga('Guardando...');

    try {
      final userAuth = FirebaseAuth.instance.currentUser;

      for (var result in _detecciones) {
        final severidad = Constantes.obtenerSeveridadPorClase(result.className);
        final colorSemaforo = Constantes.obtenerColorSemaforo(severidad);

        final deteccion = Deteccion(
          id: null,
          idMazorca: widget.idMazorca,
          grupoImagen: widget.grupoImagen,
          idUsuario: widget.cedulaUsuario,
          workerId: userAuth?.uid,
          fase: result.className,
          confianza: result.confidence,
          severidad: severidad,
          colorSemaforo: colorSemaforo,
          rutaImagen: imagenFile.path,
          fecha: DateTime.now(),
          latitud: coordenadas['latitud']!,
          longitud: coordenadas['longitud']!,
          direccion: direccion,
          lote: null,
          notas: 'Seguimiento de mazorca',
          sincronizado: false,
        );

        await _bd.insertarDeteccion(deteccion);
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      if (userAuth != null) {
        _mostrarDialogoCarga('Sincronizando...');
        try {
          await _sincronizacion.sincronizarTodo();
          if (!mounted) return;
          Navigator.of(context).pop();
          _mostrarMensaje('✅ Guardado y sincronizado');
        } catch (e) {
          if (!mounted) return;
          Navigator.of(context).pop();
          _mostrarMensaje('✅ Guardado. Se sincronizará después');
        }
      } else {
        _mostrarMensaje('✅ Guardado localmente');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                DetalleDeteccionScreen(grupoImagen: widget.grupoImagen),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _mostrarMensaje('Error: $e');
    }
  }

  void _mostrarDialogoCarga(String mensaje) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(mensaje),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  void dispose() {
    _servicioIA.cerrarModelo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_inicializado) {
      return Scaffold(
        backgroundColor: TemaApp.colorFondo,
        appBar: AppBar(
          title: const Text('Inicializando...'),
          backgroundColor: TemaApp.verdePrimario,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando modelo YOLO26...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Seguimiento'),
        backgroundColor: TemaApp.verdePrimario,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timeline, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  widget.idMazorca.substring(0, 8),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (_fps > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _fps >= 25
                    ? TemaApp.verdeSecundario
                    : TemaApp.colorAdvertencia,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_fps.toStringAsFixed(0)} FPS',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: YOLOView(
              modelPath: 'yolo26n',
              task: YOLOTask.detect,
              confidenceThreshold: Constantes.umbralConfianza,
              iouThreshold: Constantes.umbralIoU,
              showOverlays: true,
              onResult: _onDeteccionesRecibidas,
              onPerformanceMetrics: _onMetricasRendimiento,
            ),
          ),
          if (_detecciones.isNotEmpty)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.eco, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_detecciones.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_latenciaMs > 0)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_latenciaMs.toStringAsFixed(0)}ms',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                onPressed: _procesando || _detecciones.isEmpty
                    ? null
                    : _capturarYGuardar,
                backgroundColor: _procesando
                    ? Colors.grey
                    : (_detecciones.isEmpty
                          ? Colors.grey.shade600
                          : Colors.blue.shade700),
                foregroundColor: Colors.white,
                icon: Icon(
                  _procesando
                      ? Icons.hourglass_empty
                      : (_detecciones.isEmpty
                            ? Icons.camera_outlined
                            : Icons.camera),
                  size: 28,
                ),
                label: Text(
                  _procesando
                      ? 'Procesando...'
                      : (_detecciones.isEmpty
                            ? 'Sin detecciones'
                            : 'Capturar (${_detecciones.length})'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          if (_procesando)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: Card(
                    margin: EdgeInsets.all(32),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Procesando...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

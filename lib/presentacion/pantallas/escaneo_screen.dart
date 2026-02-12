// lib/presentacion/pantallas/escaneo_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:uuid/uuid.dart';
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

class EscaneoScreen extends StatefulWidget {
  final String cedulaUsuario;
  final String? idMazorcaSeguimiento;
  final String? grupoImagenSeguimiento;

  const EscaneoScreen({
    super.key,
    required this.cedulaUsuario,
    this.idMazorcaSeguimiento,
    this.grupoImagenSeguimiento,
  });

  @override
  State<EscaneoScreen> createState() => _EscaneoScreenState();
}

class _EscaneoScreenState extends State<EscaneoScreen> {
  final ServicioIA _servicioIA = ServicioIA();
  final ServicioGPS _servicioGPS = ServicioGPS();
  final BaseDatosHelper _bd = BaseDatosHelper();
  final ServicioSincronizacion _sincronizacion = ServicioSincronizacion();

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  bool _inicializado = false;
  bool _procesando = false;

  List<YOLOResult> _detecciones = [];
  double _fps = 0;

  bool get _esModoSeguimiento => widget.idMazorcaSeguimiento != null;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      await _servicioIA.cargarModelo();
      _cameras = await availableCameras();

      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
      }

      setState(() => _inicializado = true);
      debugPrint('✅ Inicializado');
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) _mostrarMensaje('Error: $e');
    }
  }

  void _onDeteccionesRecibidas(List<YOLOResult> results) {
    if (_procesando || !mounted) return;
    setState(() => _detecciones = results);
  }

  Future<void> _capturarYGuardar() async {
    if (_detecciones.isEmpty) {
      _mostrarMensaje('No hay detecciones');
      return;
    }
    if (_procesando) return;

    setState(() => _procesando = true);

    try {
      _mostrarDialogoCarga('📸 Capturando...');

      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        throw Exception('Cámara no disponible');
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempPath = '${tempDir.path}/capture_$timestamp.jpg';

      final imageFile = await _cameraController!.takePicture();
      final capturedFile = File(imageFile.path);
      final tempFile = await capturedFile.copy(tempPath);

      debugPrint('📸 Capturada: ${tempFile.path}');

      if (!mounted) return;
      Navigator.of(context).pop();

      _mostrarDialogoCarga('🎨 Dibujando...');

      final imagenAnotada = await _servicioIA.dibujarAnotacionesEnImagen(
        imagenOriginal: tempFile,
        detecciones: _detecciones,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      _mostrarDialogoCarga('📍 Ubicación...');

      final coordenadas = await _servicioGPS.obtenerCoordenadas();
      final direccion = await _servicioGPS.obtenerDireccion(
        coordenadas['latitud']!,
        coordenadas['longitud']!,
      );

      final directorioApp = await getApplicationDocumentsDirectory();
      final nombreArchivo = 'deteccion_$timestamp.jpg';
      final rutaDestino = '${directorioApp.path}/$nombreArchivo';
      final imagenFinal = await imagenAnotada.copy(rutaDestino);

      if (!mounted) return;
      Navigator.of(context).pop();

      await _mostrarDialogoGuardar(imagenFinal, coordenadas, direccion);

      try {
        await tempFile.delete();
        await imagenAnotada.delete();
      } catch (e) {
        debugPrint('⚠️ Error limpiando: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error: $e');
      debugPrint('$stackTrace');
      if (mounted) Navigator.of(context).pop();
      _mostrarMensaje('Error: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _mostrarDialogoGuardar(
    File imagenFile,
    Map<String, double> coordenadas,
    String? direccion,
  ) async {
    final controladorLote = TextEditingController();
    final controladorNotas = TextEditingController();

    final todasDetecciones = _servicioIA.procesarResultadosYOLO(_detecciones);
    final totalDetecciones = todasDetecciones.length;

    final titulo = _esModoSeguimiento
        ? 'Guardar Seguimiento'
        : 'Guardar $totalDetecciones Detección${totalDetecciones > 1 ? 'es' : ''}';

    final mensaje = _esModoSeguimiento
        ? 'Se agregarán $totalDetecciones nuevo(s) registro(s)'
        : 'Se detectaron $totalDetecciones mazorca${totalDetecciones > 1 ? 's' : ''}';

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _esModoSeguimiento
                      ? Colors.blue.shade50
                      : TemaApp.verdeClaro.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _esModoSeguimiento
                        ? Colors.blue.shade200
                        : TemaApp.verdeSecundario,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _esModoSeguimiento ? Icons.timeline : Icons.eco,
                          color: _esModoSeguimiento
                              ? Colors.blue.shade700
                              : TemaApp.verdePrimario,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            mensaje,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _esModoSeguimiento
                                  ? Colors.blue.shade900
                                  : TemaApp.verdePrimario,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...todasDetecciones.map((det) {
                      final fase = det['fase'] as String;
                      final confianza = det['confianza'] as double;
                      final colorSemaforo = det['colorSemaforo'] as String;

                      Color color;
                      switch (colorSemaforo) {
                        case 'verde':
                          color = TemaApp.verdeSecundario;
                          break;
                        case 'amarillo':
                          color = TemaApp.colorAdvertencia;
                          break;
                        case 'naranja':
                          color = Colors.orange;
                          break;
                        default:
                          color = Colors.grey;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${Constantes.obtenerNombreClase(fase)} (${(confianza * 100).toStringAsFixed(0)}%)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controladorLote,
                decoration: InputDecoration(
                  labelText: 'Lote (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controladorNotas,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.note_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controladorLote.dispose();
              controladorNotas.dispose();
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaApp.verdePrimario,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (resultado == true && mounted) {
      await _guardarDetecciones(
        imagenFile,
        coordenadas,
        direccion,
        controladorLote.text,
        controladorNotas.text,
      );
    }

    controladorLote.dispose();
    controladorNotas.dispose();
  }

  Future<void> _guardarDetecciones(
    File imagenFile,
    Map<String, double> coordenadas,
    String? direccion,
    String lote,
    String notas,
  ) async {
    _mostrarDialogoCarga('💾 Guardando...');

    try {
      final grupoImagen =
          widget.grupoImagenSeguimiento ?? const Uuid().v4().substring(0, 8);
      final userAuth = FirebaseAuth.instance.currentUser;

      for (var i = 0; i < _detecciones.length; i++) {
        final result = _detecciones[i];
        final severidad = Constantes.obtenerSeveridadPorClase(result.className);
        final colorSemaforo = Constantes.obtenerColorSemaforo(severidad);

        final deteccion = Deteccion(
          id: null,
          idMazorca: widget.idMazorcaSeguimiento ?? const Uuid().v4(),
          grupoImagen: grupoImagen,
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
          lote: lote.isNotEmpty ? lote : null,
          notas: notas.isNotEmpty ? notas : null,
          sincronizado: false,
        );

        await _bd.insertarDeteccion(deteccion);
      }

      debugPrint('✅ ${_detecciones.length} guardadas');

      if (!mounted) return;
      Navigator.of(context).pop();

      if (userAuth != null) {
        _mostrarDialogoCarga('☁️ Sincronizando...');
        try {
          await _sincronizacion.sincronizarTodo();
          debugPrint('✅ Sincronizado');
          if (!mounted) return;
          Navigator.of(context).pop();
          _mostrarMensaje('✅ Guardado y sincronizado');
        } catch (e) {
          debugPrint('⚠️ Error sync: $e');
          if (!mounted) return;
          Navigator.of(context).pop();
          _mostrarMensaje('✅ Guardado. Sincronizará después');
        }
      } else {
        _mostrarMensaje('✅ Guardado localmente');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                DetalleDeteccionScreen(grupoImagen: grupoImagen),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error: $e');
      debugPrint('$stackTrace');
      if (mounted) Navigator.of(context).pop();
      _mostrarMensaje('❌ Error: $e');
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
    _cameraController?.dispose();
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
              Text('Cargando YOLO26...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_esModoSeguimiento ? 'Seguimiento' : 'Escaneo'),
        backgroundColor: TemaApp.verdePrimario,
        foregroundColor: Colors.white,
        actions: [
          if (_fps > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _fps >= 20
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
          // YOLOView con detección en tiempo real
          Positioned.fill(
            child: YOLOView(
              modelPath: Constantes.rutaModelo,
              task: YOLOTask.detect,
              confidenceThreshold: Constantes.umbralConfianza,
              iouThreshold: Constantes.umbralIoU,
              showOverlays: true,
              onResult: _onDeteccionesRecibidas,
              onPerformanceMetrics: (metrics) {
                if (mounted) setState(() => _fps = metrics.fps);
              },
            ),
          ),

          // Contador
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
                  color: TemaApp.verdeSecundario,
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

          // Botón captura
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
                          : TemaApp.verdeSecundario),
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
        ],
      ),
    );
  }
}

// lib/presentacion/pantallas/escaneo_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../logica/servicios/servicio_ia.dart';
import '../../logica/servicios/servicio_gps.dart';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  bool _inicializado = false;
  bool _procesando = false;

  List<YOLOResult> _detecciones = [];
  double _fps = 0;
  Size? _previewSize;

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
        _previewSize = _cameraController!.value.previewSize;
      }

      setState(() => _inicializado = true);
      debugPrint('✅ Cámara y modelo inicializados');
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

      final imageFile = await _cameraController!.takePicture();
      final capturedFile = File(imageFile.path);

      if (!mounted) return;
      Navigator.of(context).pop();

      _mostrarDialogoCarga('🎨 Dibujando...');

      final imagenAnotada = await _servicioIA.dibujarAnotacionesEnImagen(
        imagenOriginal: capturedFile,
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
      final nombreArchivo =
          'deteccion_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final rutaDestino = '${directorioApp.path}/$nombreArchivo';
      final imagenFinal = await imagenAnotada.copy(rutaDestino);

      if (!mounted) return;
      Navigator.of(context).pop();

      await _mostrarDialogoGuardar(imagenFinal, coordenadas, direccion);

      try {
        await capturedFile.delete();
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

    final totalDetecciones = _detecciones.length;

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          _esModoSeguimiento ? 'Guardar Seguimiento' : 'Guardar Detecciones',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$totalDetecciones detección${totalDetecciones > 1 ? 'es' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
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

      debugPrint('✅ ${_detecciones.length} guardadas en SQLite');

      if (!mounted) return;
      Navigator.of(context).pop();

      if (userAuth != null) {
        _mostrarDialogoCarga('☁️ Sincronizando...');
        try {
          await _subirAFirebase(
            imagenFile,
            grupoImagen,
            coordenadas,
            direccion,
            lote,
            notas,
          );

          if (!mounted) return;
          Navigator.of(context).pop();
          _mostrarMensaje('✅ Guardado y sincronizado');
        } catch (e) {
          debugPrint('⚠️ Error Firebase: $e');
          if (!mounted) return;
          Navigator.of(context).pop();
          _mostrarMensaje('✅ Guardado localmente');
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

  Future<void> _subirAFirebase(
    File imagenFile,
    String grupoImagen,
    Map<String, double> coordenadas,
    String? direccion,
    String lote,
    String notas,
  ) async {
    try {
      final userAuth = FirebaseAuth.instance.currentUser;
      if (userAuth == null) throw Exception('No autenticado');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = _storage.ref().child(
        'detecciones/${userAuth.uid}/${grupoImagen}_$timestamp.jpg',
      );

      await storageRef.putFile(imagenFile);
      final imagenUrl = await storageRef.getDownloadURL();

      debugPrint('✅ Imagen subida: $imagenUrl');

      for (var i = 0; i < _detecciones.length; i++) {
        final result = _detecciones[i];
        final severidad = Constantes.obtenerSeveridadPorClase(result.className);
        final colorSemaforo = Constantes.obtenerColorSemaforo(severidad);

        final data = {
          'idMazorca': widget.idMazorcaSeguimiento ?? const Uuid().v4(),
          'grupoImagen': grupoImagen,
          'idUsuario': widget.cedulaUsuario,
          'workerId': userAuth.uid,
          'fase': result.className,
          'confianza': result.confidence,
          'severidad': severidad,
          'colorSemaforo': colorSemaforo,
          'imagenUrl': imagenUrl,
          'timestamp': FieldValue.serverTimestamp(),
          'latitud': coordenadas['latitud']!,
          'longitud': coordenadas['longitud']!,
          'direccion': direccion,
          'lote': lote.isNotEmpty ? lote : null,
          'notas': notas.isNotEmpty ? notas : null,
        };

        await _firestore.collection('detecciones').add(data);
      }

      debugPrint('✅ Firestore actualizado');

      final deteccionesLocales = await _bd.obtenerDeteccionesPorGrupo(
        grupoImagen,
      );
      for (final det in deteccionesLocales) {
        await _bd.actualizarDeteccion(
          det.copyWith(sincronizado: true, rutaImagen: imagenUrl),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error Firebase: $e');
      debugPrint('$stackTrace');
      rethrow;
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
          Positioned.fill(
            child: YOLOView(
              modelPath: Constantes.rutaModelo,
              task: YOLOTask.detect,
              confidenceThreshold: Constantes.umbralConfianza,
              iouThreshold: Constantes.umbralIoU,
              showOverlays: false,
              onResult: _onDeteccionesRecibidas,
              onPerformanceMetrics: (metrics) {
                if (mounted) setState(() => _fps = metrics.fps);
              },
            ),
          ),
          if (_detecciones.isNotEmpty && _previewSize != null)
            Positioned.fill(
              child: CustomPaint(
                painter: YOLOOverlayPainter(
                  detecciones: _detecciones,
                  previewSize: _previewSize!,
                  screenSize: MediaQuery.of(context).size,
                ),
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

class YOLOOverlayPainter extends CustomPainter {
  final List<YOLOResult> detecciones;
  final Size previewSize;
  final Size screenSize;

  YOLOOverlayPainter({
    required this.detecciones,
    required this.previewSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final deteccion in detecciones) {
      final box = deteccion.boundingBox;
      final scaleX = size.width / previewSize.width;
      final scaleY = size.height / previewSize.height;

      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      final severidad = Constantes.obtenerSeveridadPorClase(
        deteccion.className,
      );
      final color = _getColorPorSeveridad(severidad);

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRect(rect, paint);

      final nombreClase = Constantes.obtenerNombreClase(deteccion.className);
      final porcentaje = '${(deteccion.confidence * 100).toStringAsFixed(0)}%';
      final texto = '$nombreClase $porcentaje';

      final textPainter = TextPainter(
        text: TextSpan(
          text: texto,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final bgRect = Rect.fromLTWH(
        rect.left,
        rect.top - 24,
        textPainter.width + 8,
        20,
      );
      canvas.drawRect(
        bgRect,
        Paint()..color = Colors.black.withValues(alpha: 0.7),
      );
      canvas.drawRect(
        bgRect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - 22));
    }
  }

  Color _getColorPorSeveridad(int severidad) {
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
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  bool shouldRepaint(covariant YOLOOverlayPainter oldDelegate) =>
      detecciones != oldDelegate.detecciones;
}

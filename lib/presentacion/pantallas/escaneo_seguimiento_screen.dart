// lib/presentacion/pantallas/escaneo_seguimiento_screen.dart
// ✅ VERSIÓN CORREGIDA
// CAMBIOS:
// - _guardarDetecciones: ya no depende de idMazorca para Firestore
// - _guardarEvaluacionEnFirestore: eliminado imagenPath (fuera del esquema)
// - _colorPinSegunFase: corregido "naranja" → "amarillo" para severidad 2
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../logica/servicios/servicio_ia.dart';
import '../../logica/servicios/servicio_gps.dart';
import '../../logica/servicios/servicio_sincronizacion.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';
import 'detalle_deteccion_screen.dart';

class EscaneoSeguimientoScreen extends StatefulWidget {
  final String cedulaUsuario;
  final String idMazorca; // en seguimiento, coincide con grupoImagen
  final String grupoImagen;
  final String? seguimientoId;

  const EscaneoSeguimientoScreen({
    super.key,
    required this.cedulaUsuario,
    required this.idMazorca,
    required this.grupoImagen,
    this.seguimientoId,
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
      _mostrarDialogoCarga('Capturando foto...');

      final XFile? foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1280,
      );

      if (foto == null) {
        if (mounted) Navigator.of(context).pop();
        setState(() => _procesando = false);
        return;
      }

      final imagenFile = File(foto.path);

      if (!mounted) return;
      Navigator.of(context).pop();

      _mostrarDialogoCarga('Dibujando anotaciones...');

      final imagenAnotada = await _servicioIA.dibujarAnotacionesEnImagen(
        imagenOriginal: imagenFile,
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
        await imagenFile.delete();
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

      // Guardar cada detección en SQLite local
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

      if (userAuth != null && widget.seguimientoId != null) {
        // Tiene seguimientoId → registrar evaluación en subcolección
        _mostrarDialogoCarga('Registrando evaluación...');
        try {
          await _guardarEvaluacionEnFirestore(
            imagenFile: imagenFile,
            uid: userAuth.uid,
          );
          if (!mounted) return;
          Navigator.of(context).pop();

          if (_detecciones.isNotEmpty) {
            await _mostrarTratamientoRecomendado(_detecciones.first.className);
          }
          _mostrarMensaje('✅ Guardado y evaluación registrada');
        } catch (e) {
          if (mounted) Navigator.of(context).pop();
          debugPrint('⚠️ Error guardando evaluación en Firestore: $e');
          _mostrarMensaje('✅ Guardado localmente. Se sincronizará después');
        }
      } else if (userAuth != null) {
        // Sin seguimientoId → sincronizar normalmente
        _mostrarDialogoCarga('Sincronizando...');
        try {
          await _sincronizacion.sincronizarTodo();
          if (!mounted) return;
          Navigator.of(context).pop();

          if (_detecciones.isNotEmpty) {
            await _mostrarTratamientoRecomendado(_detecciones.first.className);
          }
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

  Future<void> _guardarEvaluacionEnFirestore({
    required File imagenFile,
    required String uid,
  }) async {
    final seguimientoId = widget.seguimientoId!;
    if (_detecciones.isEmpty) return;

    final result = _detecciones.first;
    final severidad = Constantes.obtenerSeveridadPorClase(result.className);
    final confianza = result.confidence;

    // Subir imagen a Storage
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'imagenes/seguimientos/$seguimientoId/eval_$ts.jpg';
    final storageRef = FirebaseStorage.instance.ref(storagePath);
    await storageRef.putFile(imagenFile);
    final imagenUrl = await storageRef.getDownloadURL();

    final segRef = FirebaseFirestore.instance.doc(
      'seguimientos/$seguimientoId',
    );

    // ✅ Solo campos necesarios, sin imagenPath (fuera del esquema)
    await segRef.collection('evaluaciones').add({
      'imagenURL': imagenUrl,
      'faseDetectada': severidad,
      'porcentajeInfeccion': confianza * 100,
      'observaciones': 'Seguimiento de mazorca',
      'fechaEvaluacion': FieldValue.serverTimestamp(),
    });

    final Map<String, dynamic> actualizacion = {
      'faseActual': severidad,
      'colorPinMapa': _colorPinSegunFase(severidad),
      'totalEvaluaciones': FieldValue.increment(1),
      'ultimaEvaluacion': FieldValue.serverTimestamp(),
    };

    if (severidad == 4) {
      actualizacion['estado'] = 'perdido';
    }

    await segRef.update(actualizacion);
    debugPrint('✅ Evaluación registrada en seguimiento $seguimientoId');
  }

  // ✅ CORREGIDO: "naranja" → "amarillo" para severidad 2 (igual que constantes.dart)
  String _colorPinSegunFase(int severidad) {
    switch (severidad) {
      case 0:
        return 'verde';
      case 1:
        return 'amarillo';
      case 2:
        return 'amarillo'; // ← era "naranja", no existe en el esquema
      case 3:
        return 'rojo';
      default:
        return 'gris';
    }
  }

  Future<void> _mostrarTratamientoRecomendado(String fase) async {
    try {
      final tratamiento = await _sincronizacion.obtenerTratamientoRecomendado(
        fase,
      );

      if (!mounted) return;

      if (tratamiento == null) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Protocolo no disponible',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No se encontró un protocolo de tratamiento para:',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TemaApp.verdeClaro.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: TemaApp.verdeSecundario),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Constantes.obtenerColorPorClase(fase),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          Constantes.obtenerNombreLegible(fase),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        color: Colors.orange.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'La administradora debe crear este protocolo '
                          'desde el panel web (sección Tratamientos).',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }

      final nombreFase = tratamiento['nombre'] as String? ?? '';
      final descripcion = tratamiento['descripcion'] as String? ?? '';
      final acciones = (tratamiento['acciones'] as List?)?.cast<String>() ?? [];
      final fungicidas =
          (tratamiento['fungicidas'] as List?)?.cast<String>() ?? [];
      final urgencia = tratamiento['urgencia'] as String? ?? 'baja';

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.medical_services,
                color: TemaApp.verdePrimario,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tratamiento: $nombreFase',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (descripcion.isNotEmpty) ...[
                  Text(
                    descripcion,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getUrgenciaColor(urgencia).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: _getUrgenciaColor(urgencia),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Urgencia: ${urgencia.toUpperCase()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getUrgenciaColor(urgencia),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (acciones.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'ACCIONES DE CAMPO:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...acciones.map(
                    (accion) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '✓ ',
                            style: TextStyle(
                              color: TemaApp.verdePrimario,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              accion,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (fungicidas.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'SUGERENCIAS QUÍMICAS:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: fungicidas
                        .map(
                          (f) => Chip(
                            label: Text(
                              f,
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor: TemaApp.verdeClaro,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: TemaApp.verdePrimario,
              ),
              child: const Text(
                'Entendido',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('❌ Error mostrando tratamiento: $e');
    }
  }

  Color _getUrgenciaColor(String urgencia) {
    switch (urgencia.toLowerCase()) {
      case 'crítica':
      case 'critica':
        return Colors.red;
      case 'alta':
        return Colors.orange;
      case 'media':
        return Colors.amber;
      default:
        return Colors.green;
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
              Text('Cargando modelo YOLO...'),
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
                  widget.idMazorca.substring(
                    0,
                    widget.idMazorca.length > 8 ? 8 : widget.idMazorca.length,
                  ),
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

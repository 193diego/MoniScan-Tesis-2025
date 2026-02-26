// lib/presentacion/pantallas/escaneo_screen.dart
// ═══════════════════════════════════════════════════════════════════════════
// DETECCIÓN EN TIEMPO REAL — ultralytics_yolo ^0.2.0
// Con logs EXHAUSTIVOS de todo lo que hace el modelo en tiempo real.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../logica/servicios/servicio_gps.dart';
import '../../logica/servicios/servicio_mazorcas.dart';
import '../../logica/servicios/servicio_sincronizacion.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';
import '../../utils/manejador_permisos.dart';

class EscaneoScreen extends StatefulWidget {
  final String usuarioId;
  final VoidCallback onVolverInicio;
  final String? grupoImagenSeguimiento;
  final String? idMazorcaSeguimiento;

  const EscaneoScreen({
    super.key,
    required this.usuarioId,
    required this.onVolverInicio,
    this.grupoImagenSeguimiento,
    this.idMazorcaSeguimiento,
  });

  @override
  State<EscaneoScreen> createState() => _EscaneoScreenState();
}

class _EscaneoScreenState extends State<EscaneoScreen>
    with WidgetsBindingObserver {
  // ── Servicios ─────────────────────────────────────────────────────────────
  final ServicioGPS _gps = ServicioGPS();
  final BaseDatosHelper _bd = BaseDatosHelper();
  final ServicioSincronizacion _sincronizacion = ServicioSincronizacion();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── YOLO ──────────────────────────────────────────────────────────────────
  final YOLOViewController _yoloController = YOLOViewController();
  final GlobalKey _repaintKey = GlobalKey();

  // ── Estado ────────────────────────────────────────────────────────────────
  bool _inicializado = false;
  bool _capturando = false;
  bool _esModoSeguimiento = false;
  bool _appEnBackground = false;
  String? _error;
  Key _yoloViewKey = UniqueKey();

  // ── Detecciones ───────────────────────────────────────────────────────────
  List<YOLOResult> _deteccionesRaw = [];
  List<YOLOResult> _deteccionesUI = [];
  YOLOPerformanceMetrics? _metricas;
  Timer? _throttleTimer;
  static const int _throttleMs = 300;

  // ── Contadores para logs ──────────────────────────────────────────────────
  int _frameCount = 0; // frames recibidos desde onResult
  int _frameConDetecciones = 0; // frames que tuvieron ≥1 detección
  DateTime _tiempoInicio = DateTime.now();
  DateTime _ultimoLogDetalle = DateTime.now(); // log detallado c/ 2 s
  DateTime _ultimoLogResumen = DateTime.now(); // resumen c/ 10 s
  double _fpsAcumulado = 0;
  int _fpsContador = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _esModoSeguimiento = widget.grupoImagenSeguimiento != null;
    _tiempoInicio = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _inicializar());

    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════╗');
    debugPrint('║         ESCANEO SCREEN — MODO DEBUG ACTIVADO            ║');
    debugPrint('║   Modelo  : best_float16.tflite                         ║');
    debugPrint(
      '║   Umbral conf  : ${Constantes.umbralConfianza}                              ║',
    );
    debugPrint(
      '║   Umbral IoU   : ${Constantes.umbralIoU}                               ║',
    );
    debugPrint('║   MaxFPS       : 30                                     ║');
    debugPrint(
      '║   ThrottleUI   : ${_throttleMs}ms                              ║',
    );
    debugPrint('╚══════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _imprimirResumenFinal();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _imprimirResumenFinal() {
    final dur = DateTime.now().difference(_tiempoInicio).inSeconds;
    final fpsPromedio = _fpsContador > 0
        ? (_fpsAcumulado / _fpsContador).toStringAsFixed(1)
        : 'N/A';
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════╗');
    debugPrint('║              RESUMEN FINAL DE SESIÓN                    ║');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║  Duración total      : ${dur}s');
    debugPrint('║  Frames procesados   : $_frameCount');
    debugPrint('║  Frames c/detección  : $_frameConDetecciones');
    debugPrint('║  FPS promedio (GPU)  : $fpsPromedio');
    debugPrint(
      '║  Tasa detección      : ${_frameCount > 0 ? ((_frameConDetecciones / _frameCount) * 100).toStringAsFixed(1) : 0}% de frames',
    );
    debugPrint('╚══════════════════════════════════════════════════════════╝');
    debugPrint('');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    debugPrint('🔄 [Lifecycle] Estado app: $state');
    setState(() => _appEnBackground = state == AppLifecycleState.paused);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INICIALIZACIÓN
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _inicializar() async {
    debugPrint('🚀 [Init] Solicitando permiso de cámara...');
    try {
      final ok = await ManejadorPermisos.solicitarPermisoCamara(context);
      if (!ok) {
        debugPrint('❌ [Init] Permiso de cámara DENEGADO');
        if (mounted) {
          setState(
            () => _error =
                'Permiso de cámara denegado.\n'
                'Ve a Ajustes → Aplicaciones → MoniScan → Permisos → Cámara.',
          );
        }
        return;
      }
      debugPrint('✅ [Init] Permiso concedido — YOLOView iniciando...');
      debugPrint(
        '📷 [Init] Modelo: best_float16  |  Task: detect  |  showOverlays: true',
      );
      if (mounted) setState(() => _inicializado = true);
    } catch (e) {
      debugPrint('❌ [Init] Error: $e');
      if (mounted) setState(() => _error = 'Error al iniciar: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALLBACK onResult — NÚCLEO DEL MODELO
  // Se llama ~30 veces/segundo por el plugin nativo.
  // NUNCA llamar setState aquí directamente (causa lag).
  // ═══════════════════════════════════════════════════════════════════════════

  void _onDeteccionesLive(List<YOLOResult> results) {
    if (_appEnBackground) return;

    _frameCount++;
    final ahora = DateTime.now();

    // ── Log detallado cada 2 segundos (o cuando hay detecciones nuevas) ──────
    final msDesdeDet = ahora.difference(_ultimoLogDetalle).inMilliseconds;
    final hayDetecciones = results.isNotEmpty;

    if (hayDetecciones) _frameConDetecciones++;

    // Log detallado: cada 2 s, o cuando aparece la primera detección
    if (msDesdeDet >= 2000 || (hayDetecciones && msDesdeDet >= 500)) {
      _ultimoLogDetalle = ahora;

      final msDesdeInicio = ahora.difference(_tiempoInicio).inMilliseconds;
      final fpsReal = _metricas?.fps ?? 0.0;
      final latencia = _metricas?.processingTimeMs ?? 0.0;

      debugPrint('');
      debugPrint('┌─────────────────────────────────────────────────────────');
      debugPrint(
        '│ 🎯 FRAME #$_frameCount  |  t=${msDesdeInicio}ms  |  ${ahora.toIso8601String().substring(11, 23)}',
      );
      debugPrint(
        '│ ⚡ FPS GPU: ${fpsReal.toStringAsFixed(1)}  |  Latencia inferencia: ${latencia.toStringAsFixed(1)}ms',
      );
      debugPrint('│ 🔍 Detecciones en este frame: ${results.length}');

      if (results.isEmpty) {
        debugPrint('│    (sin detecciones — escena limpia o baja confianza)');
      } else {
        debugPrint('│');
        for (int i = 0; i < results.length; i++) {
          final r = results[i];
          final box = r.boundingBox;
          final sev = Constantes.obtenerSeveridadPorClase(r.className);
          final sevLabel = _labelSev(sev);
          final w = (box.right - box.left);
          final h = (box.bottom - box.top);
          final cx = (box.left + box.right) / 2;
          final cy = (box.top + box.bottom) / 2;

          debugPrint('│  [$i] ────────────────────────────────────────────');
          debugPrint('│      Clase      : ${r.className}');
          debugPrint(
            '│      Confianza  : ${(r.confidence * 100).toStringAsFixed(2)}%',
          );
          debugPrint('│      Severidad  : $sev ($sevLabel)');
          debugPrint('│      BoundingBox:');
          debugPrint('│        left   = ${box.left.toStringAsFixed(4)}');
          debugPrint('│        top    = ${box.top.toStringAsFixed(4)}');
          debugPrint('│        right  = ${box.right.toStringAsFixed(4)}');
          debugPrint('│        bottom = ${box.bottom.toStringAsFixed(4)}');
          debugPrint('│        width  = ${w.toStringAsFixed(4)}');
          debugPrint('│        height = ${h.toStringAsFixed(4)}');
          debugPrint(
            '│        center = (${cx.toStringAsFixed(4)}, ${cy.toStringAsFixed(4)})',
          );
          debugPrint(
            '│        formato: ${(box.right > 1.5 || box.bottom > 1.5) ? "PÍXELES" : "NORMALIZADO [0-1]"}',
          );
        }
      }
      debugPrint('└─────────────────────────────────────────────────────────');
    }

    // ── Log resumen cada 10 segundos ─────────────────────────────────────────
    final msDesdeRes = ahora.difference(_ultimoLogResumen).inMilliseconds;
    if (msDesdeRes >= 10000) {
      _ultimoLogResumen = ahora;
      final fpsReal = _metricas?.fps ?? 0.0;
      final pctDet = _frameCount > 0
          ? (_frameConDetecciones / _frameCount * 100).toStringAsFixed(1)
          : '0.0';

      debugPrint('');
      debugPrint(
        '╔══════════ RESUMEN 10 s ══════════════════════════════════╗',
      );
      debugPrint('║  Frames totales      : $_frameCount');
      debugPrint('║  Frames c/detección  : $_frameConDetecciones  ($pctDet%)');
      debugPrint('║  FPS actual (GPU)    : ${fpsReal.toStringAsFixed(1)}');
      if (_metricas != null) {
        debugPrint(
          '║  Latencia promedio   : ${_metricas!.processingTimeMs.toStringAsFixed(1)} ms',
        );
      }
      debugPrint(
        '╚══════════════════════════════════════════════════════════╝',
      );
    }

    // ── Actualizar estado raw (sin setState) ──────────────────────────────────
    if (_capturando) return;
    _deteccionesRaw = results;

    // Throttle UI: solo rebuild cada 300ms
    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      _throttleTimer = Timer(Duration(milliseconds: _throttleMs), () {
        if (mounted && !_capturando) {
          setState(() => _deteccionesUI = List.from(_deteccionesRaw));
        }
      });
    }
  }

  // ── Callback de métricas de performance ───────────────────────────────────
  void _onMetricas(YOLOPerformanceMetrics metrics) {
    // Acumular para promedio
    _fpsAcumulado += metrics.fps;
    _fpsContador++;

    // Log de métricas cada 5 s
    final ahora = DateTime.now();
    if (_fpsContador == 1 || _fpsContador % 150 == 0) {
      debugPrint('');
      debugPrint('📊 [Métricas GPU]');
      debugPrint('   FPS            : ${metrics.fps.toStringAsFixed(2)}');
      debugPrint(
        '   Latencia       : ${metrics.processingTimeMs.toStringAsFixed(2)} ms',
      );
      debugPrint(
        '   FPS promedio   : ${(_fpsAcumulado / _fpsContador).toStringAsFixed(2)}',
      );
    }

    _metricas = metrics;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CAPTURA
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _capturarYAnalizar() async {
    if (_capturando) return;

    final snap = List<YOLOResult>.from(_deteccionesRaw);
    debugPrint('');
    debugPrint('📸 ════════════ CAPTURA INICIADA ════════════════════════════');
    debugPrint('📸 Detecciones en el momento: ${snap.length}');

    if (snap.isEmpty) {
      _mostrarMensaje('⚠️ No hay mazorcas detectadas. Acerca más la cámara.');
      debugPrint('⚠️ [Captura] Abortada — sin detecciones');
      return;
    }

    setState(() => _capturando = true);

    try {
      _mostrarDialogoProgreso('Capturando imagen...');
      File? imagenCapturada;

      debugPrint('📸 [Captura] Intentando RepaintBoundary.toImage()...');
      try {
        final boundary =
            _repaintKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData != null) {
            final tmpDir = await getTemporaryDirectory();
            final ruta =
                '${tmpDir.path}/cap_${DateTime.now().millisecondsSinceEpoch}.png';
            imagenCapturada = await File(
              ruta,
            ).writeAsBytes(byteData.buffer.asUint8List());
            debugPrint(
              '✅ [Captura] Screenshot OK — ${imagenCapturada.lengthSync()} bytes → $ruta',
            );
          }
        } else {
          debugPrint('⚠️ [Captura] RenderRepaintBoundary es null');
        }
      } catch (e) {
        debugPrint('⚠️ [Captura] Screenshot falló: $e  → usando fallback JPEG');
      }

      imagenCapturada ??= await _crearImagenFallback();
      debugPrint('📸 [Captura] Imagen final: ${imagenCapturada.path}');

      // Log de todas las detecciones capturadas
      debugPrint('📸 [Captura] Detecciones capturadas:');
      for (int i = 0; i < snap.length; i++) {
        final r = snap[i];
        final box = r.boundingBox;
        final sev = Constantes.obtenerSeveridadPorClase(r.className);
        debugPrint(
          '  [$i] ${r.className} | conf=${(r.confidence * 100).toStringAsFixed(2)}% | sev=$sev | '
          'box=[${box.left.toStringAsFixed(3)}, ${box.top.toStringAsFixed(3)}, '
          '${box.right.toStringAsFixed(3)}, ${box.bottom.toStringAsFixed(3)}]',
        );
      }

      final resultados = snap.map((r) {
        final sev = Constantes.obtenerSeveridadPorClase(r.className);
        return <String, dynamic>{
          'tag': r.className,
          'confianza': r.confidence,
          'severidad': sev,
          'colorSemaforo': Constantes.obtenerColorSemaforo(sev),
          'box': [
            r.boundingBox.left,
            r.boundingBox.top,
            r.boundingBox.right,
            r.boundingBox.bottom,
          ],
        };
      }).toList();

      _actualizarDialogoProgreso('Obteniendo ubicación...');
      Map<String, double> coords = {'latitud': 0.0, 'longitud': 0.0};
      String? direccion;
      try {
        coords = await _gps.obtenerCoordenadas();
        direccion = await _gps.obtenerDireccion(
          coords['latitud']!,
          coords['longitud']!,
        );
        debugPrint(
          '📍 [GPS] lat=${coords['latitud']} lon=${coords['longitud']} dir=$direccion',
        );
      } catch (e) {
        debugPrint('⚠️ [GPS] $e');
      }

      if (!mounted) return;
      try {
        Navigator.of(context).pop();
      } catch (_) {}

      await _mostrarDialogoGuardar(
        imagenCapturada,
        resultados,
        coords,
        direccion,
      );
    } catch (e, st) {
      debugPrint('❌ [Captura] Error inesperado: $e\n$st');
      if (!mounted) return;
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      _mostrarMensaje('Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _capturando = false);
      debugPrint(
        '📸 ════════════ CAPTURA FINALIZADA ══════════════════════════',
      );
      debugPrint('');
    }
  }

  Future<File> _crearImagenFallback() async {
    debugPrint('🖼️ [Fallback] Creando JPEG mínimo 1×1px...');
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/fallback_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes([
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
      0xFF,
      0xDB,
      0x00,
      0x43,
      0x00,
      0x08,
      0x06,
      0x06,
      0x07,
      0x06,
      0x05,
      0x08,
      0x07,
      0x07,
      0x07,
      0x09,
      0x09,
      0x08,
      0x0A,
      0x0C,
      0x14,
      0x0D,
      0x0C,
      0x0B,
      0x0B,
      0x0C,
      0x19,
      0x12,
      0x13,
      0x0F,
      0x14,
      0x1D,
      0x1A,
      0x1F,
      0x1E,
      0x1D,
      0x1A,
      0x1C,
      0x1C,
      0x20,
      0x24,
      0x2E,
      0x27,
      0x20,
      0x22,
      0x2C,
      0x23,
      0x1C,
      0x1C,
      0x28,
      0x37,
      0x29,
      0x2C,
      0x30,
      0x31,
      0x34,
      0x34,
      0x34,
      0x1F,
      0x27,
      0x39,
      0x3D,
      0x38,
      0x32,
      0x3C,
      0x2E,
      0x33,
      0x34,
      0x32,
      0xFF,
      0xC0,
      0x00,
      0x0B,
      0x08,
      0x00,
      0x01,
      0x00,
      0x01,
      0x01,
      0x01,
      0x11,
      0x00,
      0xFF,
      0xC4,
      0x00,
      0x1F,
      0x00,
      0x00,
      0x01,
      0x05,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0xFF,
      0xDA,
      0x00,
      0x08,
      0x01,
      0x01,
      0x00,
      0x00,
      0x3F,
      0x00,
      0xFB,
      0xD3,
      0xFF,
      0xD9,
    ]);
    debugPrint('🖼️ [Fallback] Creado: ${file.path}');
    return file;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIÁLOGOS
  // ═══════════════════════════════════════════════════════════════════════════

  void _mostrarDialogoProgreso(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(color: TemaApp.verdePrimario),
              const SizedBox(width: 20),
              Expanded(child: Text(msg)),
            ],
          ),
        ),
      ),
    );
  }

  void _actualizarDialogoProgreso(String msg) {
    if (!mounted) return;
    try {
      Navigator.of(context).pop();
    } catch (_) {}
    _mostrarDialogoProgreso(msg);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIÁLOGO GUARDAR
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _mostrarDialogoGuardar(
    File imagen,
    List<Map<String, dynamic>> resultados,
    Map<String, double> coords,
    String? dir,
  ) async {
    String? loteId;
    String? loteNombre;
    final notasCtrl = TextEditingController();

    List<Map<String, String>> lotes = [];
    try {
      final snap = await _firestore
          .collection('lotes')
          .where('activo', isEqualTo: true)
          .get();
      lotes = snap.docs
          .map(
            (d) => {
              'id': d.id,
              'nombre': (d.data()['nombre'] as String?) ?? 'Sin nombre',
            },
          )
          .toList();
      debugPrint('🗂️ [Lotes] Cargados: ${lotes.length}');
    } catch (e) {
      debugPrint('⚠️ [Lotes] $e');
    }

    if (!mounted) return;
    final tieneImagenReal =
        await imagen.exists() && await imagen.length() > 5000;
    debugPrint(
      '🖼️ [Diálogo] Imagen válida: $tieneImagenReal (${await imagen.length()} bytes)',
    );
    if (!mounted) return;

    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.save_alt, color: TemaApp.verdePrimario),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Guardar ${resultados.length} '
                  'detección${resultados.length > 1 ? "es" : ""}',
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Imagen capturada ─────────────────────────────────────────
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: tieneImagenReal
                        ? Image.file(
                            imagen,
                            height: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint(
                                '⚠️ [Image.file] Error cargando imagen: $error',
                              );
                              return _sinImagen();
                            },
                          )
                        : _sinImagen(),
                  ),
                ),
                if (tieneImagenReal)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Center(
                      child: Text(
                        'Imagen capturada con detecciones YOLO',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                // ── Lista de detecciones ──────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detecciones:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      ...resultados.map((r) {
                        final clase = r['tag'] as String;
                        final conf = r['confianza'] as double;
                        final sev = r['severidad'] as int;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Constantes.obtenerColorPorClase(clase),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${Constantes.obtenerNombreLegible(clase)} — '
                                  '${(conf * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _colorSev(sev),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _labelSev(sev),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
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
                const SizedBox(height: 14),

                // ── Selector de lote ─────────────────────────────────────────
                if (lotes.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Lote (opcional)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    hint: const Text('Selecciona un lote'),
                    initialValue: loteId,
                    isExpanded: true,
                    items: lotes
                        .map(
                          (l) => DropdownMenuItem<String>(
                            value: l['id'],
                            child: Text(
                              l['nombre']!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setDialog(() {
                      loteId = val;
                      loteNombre = lotes.firstWhere(
                        (l) => l['id'] == val,
                      )['nombre'];
                    }),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Notas ────────────────────────────────────────────────────
                TextField(
                  controller: notasCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemaApp.verdePrimario,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (guardado == true) {
      debugPrint('💾 [Diálogo] Usuario confirmó guardar');
      _ejecutarGuardadoAsync(
        imagen,
        resultados,
        coords,
        dir,
        loteId,
        loteNombre,
        notasCtrl.text.trim(),
      );
    } else {
      debugPrint('🚫 [Diálogo] Usuario canceló guardar');
    }
  }

  Widget _sinImagen() => Container(
    height: 180,
    color: Colors.grey.shade200,
    child: const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: Colors.grey,
          ),
          SizedBox(height: 8),
          Text(
            'Vista previa no disponible',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Color _colorSev(int sev) {
    switch (sev) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _labelSev(int sev) {
    switch (sev) {
      case 0:
        return 'SANA';
      case 1:
        return 'INICIAL';
      case 2:
        return 'MEDIA';
      case 3:
        return 'AVANZADA';
      default:
        return '';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDAR EN BD (fire and forget)
  // ═══════════════════════════════════════════════════════════════════════════

  void _ejecutarGuardadoAsync(
    File imagen,
    List<Map<String, dynamic>> resultados,
    Map<String, double> coords,
    String? dir,
    String? loteId,
    String? loteNombre,
    String notas,
  ) {
    Future(() async {
      debugPrint('');
      debugPrint(
        '💾 ════════════ GUARDANDO EN BD ═════════════════════════════',
      );
      try {
        final grupo = _esModoSeguimiento
            ? widget.grupoImagenSeguimiento!
            : const Uuid().v4().substring(0, 8);
        final user = FirebaseAuth.instance.currentUser;
        final svcMazorcas = ServicioMazorcas();
        int guardadas = 0;

        debugPrint('💾 Grupo: $grupo  |  Usuario: ${user?.uid ?? "anon"}');
        debugPrint('💾 Lote: $loteNombre ($loteId)');
        debugPrint('💾 Notas: "${notas.isEmpty ? "(vacías)" : notas}"');

        for (final r in resultados) {
          final clase = r['tag'] as String;
          final conf = r['confianza'] as double;
          final sev = r['severidad'] as int;

          debugPrint(
            '💾 Guardando [$guardadas]: $clase conf=${(conf * 100).toStringAsFixed(1)}% sev=$sev',
          );

          String idMazorca;
          if (_esModoSeguimiento) {
            idMazorca = widget.idMazorcaSeguimiento!;
            debugPrint('   → Modo seguimiento, idMazorca=$idMazorca');
          } else {
            try {
              final sug = await svcMazorcas.obtenerSugerenciaId(
                idUsuario: widget.usuarioId,
                latitud: coords['latitud']!,
                longitud: coords['longitud']!,
                lote: loteNombre,
              );
              idMazorca = sug['idMazorca'] as String;
              debugPrint('   → idMazorca sugerido: $idMazorca');
            } catch (e) {
              idMazorca = const Uuid().v4();
              debugPrint('   → idMazorca generado (fallback): $idMazorca');
            }
          }

          await _bd.insertarDeteccion(
            Deteccion(
              id: null,
              idMazorca: idMazorca,
              grupoImagen: grupo,
              idUsuario: widget.usuarioId,
              workerId: user?.uid,
              fase: clase,
              confianza: conf,
              severidad: sev,
              colorSemaforo: Constantes.obtenerColorSemaforo(sev),
              rutaImagen: imagen.path,
              fecha: DateTime.now(),
              latitud: coords['latitud']!,
              longitud: coords['longitud']!,
              direccion: dir,
              lote: loteNombre,
              loteId: loteId,
              notas: notas,
              sincronizado: false,
            ),
          );
          guardadas++;
          debugPrint('   ✅ Insertado en SQLite');
        }

        debugPrint('💾 Total guardadas: $guardadas');
        debugPrint(
          '💾 ═══════════════════════════════════════════════════════════',
        );

        if (resultados.isNotEmpty) {
          final masGrave = resultados.reduce(
            (a, b) =>
                (a['severidad'] as int) >= (b['severidad'] as int) ? a : b,
          );
          debugPrint('🏥 Tratamiento para: ${masGrave['tag']}');
          await _mostrarTratamiento(masGrave['tag'] as String);
        }

        if (mounted) {
          _mostrarMensaje(
            '✅ $guardadas detección${guardadas > 1 ? "es" : ""} '
            'guardada${guardadas > 1 ? "s" : ""}',
          );
          Future.delayed(const Duration(seconds: 1), widget.onVolverInicio);
        }
      } catch (e, st) {
        debugPrint('❌ [BD] Error guardando: $e\n$st');
        if (mounted) _mostrarMensaje('Error al guardar: $e');
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRATAMIENTO RECOMENDADO
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _mostrarTratamiento(String fase) async {
    try {
      debugPrint('🏥 [Tratamiento] Buscando para fase="$fase"...');
      final t = await _sincronizacion.obtenerTratamientoRecomendado(fase);
      if (!mounted) return;

      if (t == null) {
        debugPrint('⚠️ [Tratamiento] No encontrado para "$fase"');
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Protocolo no disponible',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No hay protocolo para esta detección.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        color: Colors.orange.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'La administradora debe crear este protocolo '
                          'desde el panel web.',
                          style: TextStyle(fontSize: 13),
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

      final nombre = t['nombre'] as String? ?? '';
      final descripcion = t['descripcion'] as String? ?? '';
      final acciones = (t['acciones'] as List?)?.cast<String>() ?? [];
      final fungicidas = (t['fungicidas'] as List?)?.cast<String>() ?? [];
      final urgencia = t['urgencia'] as String? ?? 'baja';
      debugPrint('✅ [Tratamiento] Encontrado: "$nombre" — urgencia=$urgencia');

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
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
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Tratamiento: $nombre',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
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
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _urgenciaColor(urgencia).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: _urgenciaColor(urgencia),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Urgencia: ${urgencia.toUpperCase()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _urgenciaColor(urgencia),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (acciones.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'ACCIONES:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...acciones.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
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
                              a,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (fungicidas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'SUGERENCIAS QUÍMICAS:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: fungicidas
                        .map(
                          (f) => Chip(
                            label: Text(
                              f,
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor: TemaApp.verdeClaro,
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
      debugPrint('❌ [Tratamiento] $e');
    }
  }

  Color _urgenciaColor(String u) {
    switch (u.toLowerCase()) {
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

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_capturando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _mostrarMensaje('Espere a que termine el proceso');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          elevation: 0,
          title: Text(
            _esModoSeguimiento ? 'Seguimiento' : 'Detectar Moniliasis',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: _capturando ? null : widget.onVolverInicio,
          ),
          actions: [
            if (_metricas != null && _metricas!.fps > 0)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _metricas!.fps >= 20
                          ? Colors.green.withValues(alpha: 0.8)
                          : Colors.orange.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_metricas!.fps.toStringAsFixed(0)} fps',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _construirCuerpo(),
      ),
    );
  }

  Widget _construirCuerpo() {
    if (_error != null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 72, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _yoloViewKey = UniqueKey();
                    });
                    _inicializar();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_inicializado) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: TemaApp.verdePrimario),
            SizedBox(height: 20),
            Text(
              'Iniciando cámara...',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // ── YOLOView con RepaintBoundary para captura ────────────────────────
        Positioned.fill(
          child: RepaintBoundary(
            key: _repaintKey,
            child: YOLOView(
              key: _yoloViewKey,
              modelPath: 'best_320_float16', // ← nombre sin ruta ni .tflite
              task: YOLOTask.detect,
              controller: _yoloController,
              confidenceThreshold: Constantes.umbralConfianza,
              iouThreshold: Constantes.umbralIoU,
              showOverlays: true, // bounding boxes en GPU
              streamingConfig: const YOLOStreamingConfig(maxFPS: 30),
              onResult: _onDeteccionesLive,
              onPerformanceMetrics: _onMetricas,
            ),
          ),
        ),

        // ── Latencia ──────────────────────────────────────────────────────────
        if (_metricas != null && _metricas!.processingTimeMs > 0)
          Positioned(
            top: kToolbarHeight + 20,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_metricas!.processingTimeMs.toStringAsFixed(0)} ms',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),

        // ── Badge detecciones ─────────────────────────────────────────────────
        if (_deteccionesUI.isNotEmpty)
          Positioned(
            top: kToolbarHeight + 20,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade700.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.eco, color: Colors.white, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    '${_deteccionesUI.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Chips de clases ───────────────────────────────────────────────────
        if (_deteccionesUI.isNotEmpty && !_appEnBackground)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _deteccionesUI.map((d) {
                    final color = Constantes.obtenerColorPorClase(d.className);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${Constantes.obtenerNombreLegible(d.className)} '
                          '${(d.confidence * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

        // ── Guía sin detecciones ──────────────────────────────────────────────
        if (_deteccionesUI.isEmpty && !_appEnBackground)
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Apunta la cámara hacia las mazorcas',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),

        // ── Botón captura ─────────────────────────────────────────────────────
        Positioned(
          bottom: 28,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _capturando ? null : _capturarYAnalizar,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _capturando ? 60 : 70,
                height: _capturando ? 60 : 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _capturando ? Colors.grey : Colors.white,
                  border: Border.all(color: TemaApp.verdePrimario, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: TemaApp.verdePrimario.withValues(alpha: 0.6),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _capturando
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          color: TemaApp.verdePrimario,
                          strokeWidth: 3,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt,
                        size: 32,
                        color: TemaApp.verdePrimario,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _mostrarMensaje(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      ),
    );
  }
}

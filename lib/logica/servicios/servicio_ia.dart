// lib/logica/servicios/servicio_ia.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import '../../config/constantes.dart';

class ServicioIA {
  // ═══════════════════════════════════════════════════════
  // ESTADO TFLITE
  // ═══════════════════════════════════════════════════════
  Interpreter? _interpreter;
  bool _modeloCargado = false;
  bool get modeloCargado => _modeloCargado;

  // ✅ Usa el tamaño 640 definido en Constantes (análisis estático)
  static const int _inputSize = Constantes.tamanoEntradaModelo; // 640

  // ═══════════════════════════════════════════════════════
  // CARGAR MODELO TFLITE (best_640_float16)
  // ═══════════════════════════════════════════════════════
  Future<void> cargarModelo() async {
    if (_modeloCargado && _interpreter != null) {
      debugPrint(
        '✅ [ServicioIA] Modelo ya cargado ($_inputSize×$_inputSize float16)',
      );
      return;
    }
    try {
      debugPrint('🔄 [ServicioIA] Cargando modelo: ${Constantes.rutaModelo}');
      debugPrint(
        '   Tamaño entrada: ${_inputSize}×$_inputSize (máxima precisión)',
      );

      // ✅ Para float16 NO usamos NNAPI (puede dar conflictos)
      // Usamos solo hilos de CPU que es más estable con float16
      final options = InterpreterOptions()..threads = 4;

      _interpreter = await Interpreter.fromAsset(
        Constantes.rutaModelo,
        options: options,
      );

      // ✅ Redimensionar tensor de entrada al tamaño correcto y asignar
      _interpreter!.resizeInputTensor(0, [1, _inputSize, _inputSize, 3]);
      _interpreter!.allocateTensors();

      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      debugPrint('✅ [ServicioIA] Modelo cargado y tensores asignados');
      for (int i = 0; i < inputTensors.length; i++) {
        debugPrint(
          '   Input[$i]  shape: ${inputTensors[i].shape}  type: ${inputTensors[i].type}',
        );
      }
      for (int i = 0; i < outputTensors.length; i++) {
        debugPrint(
          '   Output[$i] shape: ${outputTensors[i].shape} type: ${outputTensors[i].type}',
        );
      }

      _modeloCargado = true;
    } catch (e, stack) {
      debugPrint('❌ [ServicioIA] Error cargando modelo: $e');
      debugPrint('Stack: $stack');
      _modeloCargado = false;
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════
  // DETECTAR EN IMAGEN CON TFLITE (análisis estático)
  // ═══════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> detectarEnImagen({
    required File archivo,
  }) async {
    debugPrint('\n🔍 ══════════════════════════════════════════════');
    debugPrint('🔍 [ServicioIA] detectarEnImagen: ${archivo.path}');
    debugPrint('🔍 ══════════════════════════════════════════════');

    final existe = await archivo.exists();
    if (!existe) throw Exception('Archivo no encontrado: ${archivo.path}');
    debugPrint('🔍 Tamaño: ${await archivo.length()} bytes');

    if (!_modeloCargado || _interpreter == null) {
      debugPrint('⚠️ Modelo no cargado, cargando ahora...');
      await cargarModelo();
    }

    try {
      // PASO 1: Leer y decodificar imagen
      debugPrint('🔵 [PASO 1] Decodificando imagen...');
      final bytes = await archivo.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('No se pudo decodificar la imagen');
      debugPrint('🔵 [PASO 1] OK — ${image.width}×${image.height} px');

      // PASO 2: Redimensionar a 640×640
      debugPrint('🔵 [PASO 2] Redimensionando a ${_inputSize}×$_inputSize...');
      final resized = img.copyResize(
        image,
        width: _inputSize,
        height: _inputSize,
      );
      debugPrint('🔵 [PASO 2] OK');

      // PASO 3: Convertir a Float32 normalizado [0,1]
      debugPrint(
        '🔵 [PASO 3] Convirtiendo a Float32 [1, $_inputSize, $_inputSize, 3]...',
      );
      final inputBytes = _imageToByteListFloat32(
        resized,
        _inputSize,
        _inputSize,
      );
      final input = inputBytes.reshape([1, _inputSize, _inputSize, 3]);
      debugPrint('🔵 [PASO 3] OK — ${inputBytes.length} valores');

      // PASO 4: Preparar buffer de salida según shape real del modelo
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final numDetecciones = outputShape.length > 1 ? outputShape[1] : 300;
      final numCampos = outputShape.length > 2 ? outputShape[2] : 6;
      debugPrint(
        '🔵 [PASO 4] Output shape: $outputShape → buffer [$numDetecciones × $numCampos]',
      );

      final output = List.generate(
        1,
        (_) => List.generate(
          numDetecciones,
          (_) => List<double>.filled(numCampos, 0),
        ),
      );

      // PASO 5: Inferencia
      debugPrint(
        '🔵 [PASO 5] Ejecutando inferencia (640×640 float16, puede tardar ~2-4s)...',
      );
      final t0 = DateTime.now();
      _interpreter!.run(input, output);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      debugPrint('🔵 [PASO 5] OK — ${ms}ms');

      // PASO 6: Log raw
      debugPrint('🔵 [PASO 6] Raw output (conf > 0.01):');
      int cnt = 0;
      for (int i = 0; i < output[0].length && cnt < 10; i++) {
        final d = output[0][i];
        if (d[4] > 0.01) {
          debugPrint(
            '  [$i] x=${d[0].toStringAsFixed(4)} y=${d[1].toStringAsFixed(4)} '
            'w=${d[2].toStringAsFixed(4)} h=${d[3].toStringAsFixed(4)} '
            'conf=${d[4].toStringAsFixed(4)} cls=${d[5].toInt()}',
          );
          cnt++;
        }
      }
      if (cnt == 0) debugPrint('  (ninguna fila con conf > 0.01)');

      // PASO 7: Post-procesar
      debugPrint('🔵 [PASO 7] Post-procesando...');
      final detecciones = _postProcess(output[0], image.width, image.height);
      debugPrint('🔵 [PASO 7] OK — ${detecciones.length} detecciones tras NMS');

      for (int i = 0; i < detecciones.length; i++) {
        final d = detecciones[i];
        final box = d['box'] as List;
        debugPrint(
          '  Det[$i] tag="${d['tag']}" '
          'conf=${((d['confianza'] as double) * 100).toStringAsFixed(1)}% '
          'box=[${box.map((v) => (v as double).toStringAsFixed(1)).join(', ')}] '
          'sev=${d['severidad']}',
        );
      }

      debugPrint('🔍 ══════════════════════════════════════════════\n');
      return detecciones;
    } catch (e, stack) {
      debugPrint('❌ [ServicioIA] Error en detección: $e\n$stack');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════
  // PREPROCESAR IMAGEN → TENSOR FLOAT32
  // ═══════════════════════════════════════════════════════
  Float32List _imageToByteListFloat32(
    img.Image image,
    int inputWidth,
    int inputHeight,
  ) {
    final buffer = Float32List(1 * inputHeight * inputWidth * 3);
    int idx = 0;
    for (int i = 0; i < inputHeight; i++) {
      for (int j = 0; j < inputWidth; j++) {
        final pixel = image.getPixel(j, i);
        buffer[idx++] = pixel.r / 255.0;
        buffer[idx++] = pixel.g / 255.0;
        buffer[idx++] = pixel.b / 255.0;
      }
    }
    return buffer;
  }

  // ═══════════════════════════════════════════════════════
  // POST-PROCESAR SALIDA DEL MODELO
  // ═══════════════════════════════════════════════════════
  List<Map<String, dynamic>> _postProcess(
    List<List<double>> output,
    int originalWidth,
    int originalHeight,
  ) {
    final detecciones = <Map<String, dynamic>>[];

    bool? isXYXY;
    for (final d in output) {
      if (d[4] >= Constantes.umbralConfianza) {
        isXYXY = (d[2] > d[0] && d[3] > d[1]);
        debugPrint(
          '🟠 [PostProc] Formato: ${isXYXY ? "x1y1x2y2 (corners)" : "cxcywh (center+size)"}',
        );
        break;
      }
    }
    if (isXYXY == null) {
      debugPrint(
        '⚠️ [PostProc] Sin detecciones con conf >= ${Constantes.umbralConfianza}',
      );
      return [];
    }

    for (final d in output) {
      final conf = d[4];
      final classId = d[5].toInt();

      if (conf < Constantes.umbralConfianza) continue;
      if (classId < 0 || classId >= Constantes.nombresClases.length) continue;

      final className = Constantes.nombresClases[classId];

      double x1, y1, x2, y2;
      if (isXYXY) {
        x1 = d[0] * originalWidth;
        y1 = d[1] * originalHeight;
        x2 = d[2] * originalWidth;
        y2 = d[3] * originalHeight;
      } else {
        final cx = d[0] * originalWidth;
        final cy = d[1] * originalHeight;
        final w = d[2] * originalWidth;
        final h = d[3] * originalHeight;
        x1 = cx - w / 2;
        y1 = cy - h / 2;
        x2 = cx + w / 2;
        y2 = cy + h / 2;
      }

      x1 = x1.clamp(0.0, originalWidth.toDouble());
      y1 = y1.clamp(0.0, originalHeight.toDouble());
      x2 = x2.clamp(0.0, originalWidth.toDouble());
      y2 = y2.clamp(0.0, originalHeight.toDouble());

      if (x2 <= x1 || y2 <= y1) continue;

      final sev = Constantes.obtenerSeveridadPorClase(className);
      final color = Constantes.obtenerColorSemaforo(sev);

      detecciones.add({
        'tag': className,
        'confidence': conf,
        'fase': className,
        'confianza': conf,
        'severidad': sev,
        'colorSemaforo': color,
        'box': [x1, y1, x2, y2],
      });
    }

    return _applyNMS(detecciones);
  }

  // ═══════════════════════════════════════════════════════
  // NMS
  // ═══════════════════════════════════════════════════════
  List<Map<String, dynamic>> _applyNMS(List<Map<String, dynamic>> boxes) {
    if (boxes.isEmpty) return [];
    boxes.sort(
      (a, b) => (b['confianza'] as double).compareTo(a['confianza'] as double),
    );
    final selected = <Map<String, dynamic>>[];
    final suppressed = List<bool>.filled(boxes.length, false);
    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      selected.add(boxes[i]);
      final boxA = boxes[i]['box'] as List;
      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        if (_calcIoU(boxA, boxes[j]['box'] as List) > Constantes.umbralIoU) {
          suppressed[j] = true;
        }
      }
    }
    return selected;
  }

  double _calcIoU(List a, List b) {
    final x1 = (a[0] as double) > (b[0] as double)
        ? a[0] as double
        : b[0] as double;
    final y1 = (a[1] as double) > (b[1] as double)
        ? a[1] as double
        : b[1] as double;
    final x2 = (a[2] as double) < (b[2] as double)
        ? a[2] as double
        : b[2] as double;
    final y2 = (a[3] as double) < (b[3] as double)
        ? a[3] as double
        : b[3] as double;
    final inter =
        ((x2 - x1).clamp(0.0, double.infinity)) *
        ((y2 - y1).clamp(0.0, double.infinity));
    final areaA =
        ((a[2] as double) - (a[0] as double)) *
        ((a[3] as double) - (a[1] as double));
    final areaB =
        ((b[2] as double) - (b[0] as double)) *
        ((b[3] as double) - (b[1] as double));
    final union = areaA + areaB - inter;
    return union > 0 ? inter / union : 0.0;
  }

  // ═══════════════════════════════════════════════════════
  // PROCESAR RESULTADOS YOLO (tiempo real → Map)
  // ═══════════════════════════════════════════════════════
  List<Map<String, dynamic>> procesarResultadosYOLO(List<YOLOResult> results) =>
      results.map((r) => _yoloResultToMap(r)).toList();

  Map<String, dynamic> procesarDeteccionYOLO(YOLOResult result) =>
      _yoloResultToMap(result);

  Map<String, dynamic> _yoloResultToMap(YOLOResult r) {
    final sev = Constantes.obtenerSeveridadPorClase(r.className);
    final color = Constantes.obtenerColorSemaforo(sev);
    return {
      'tag': r.className,
      'confidence': r.confidence,
      'fase': r.className,
      'confianza': r.confidence,
      'severidad': sev,
      'colorSemaforo': color,
      'box': [
        r.boundingBox.left,
        r.boundingBox.top,
        r.boundingBox.right,
        r.boundingBox.bottom,
      ],
    };
  }

  Map<String, dynamic> procesarDeteccion(Map<String, dynamic> deteccion) {
    final tag = deteccion['tag'] as String? ?? deteccion['fase'] as String;
    final conf =
        deteccion['confidence'] as double? ?? deteccion['confianza'] as double;
    final sev = Constantes.obtenerSeveridadPorClase(tag);
    final color = Constantes.obtenerColorSemaforo(sev);
    return {
      'fase': tag,
      'confianza': conf,
      'severidad': sev,
      'colorSemaforo': color,
    };
  }

  // ═══════════════════════════════════════════════════════
  // DIBUJAR ANOTACIONES — YOLOResult (tiempo real)
  // ═══════════════════════════════════════════════════════
  Future<File> dibujarAnotacionesEnImagen({
    required File imagenOriginal,
    required List<YOLOResult> detecciones,
  }) async {
    return _dibujarImpl(imagenOriginal, yoloResults: detecciones);
  }

  // ═══════════════════════════════════════════════════════
  // DIBUJAR ANOTACIONES — Map (análisis estático TFLite)
  // ═══════════════════════════════════════════════════════
  Future<File> dibujarAnotacionesEnImagenMap({
    required File imagenOriginal,
    required List<Map<String, dynamic>> detecciones,
  }) async {
    return _dibujarImpl(imagenOriginal, mapResults: detecciones);
  }

  // ═══════════════════════════════════════════════════════
  // IMPLEMENTACIÓN UNIFICADA DE DIBUJO
  // ═══════════════════════════════════════════════════════
  Future<File> _dibujarImpl(
    File imagenOriginal, {
    List<YOLOResult>? yoloResults,
    List<Map<String, dynamic>>? mapResults,
  }) async {
    debugPrint('\n🎨 [_dibujarImpl] INICIO: ${imagenOriginal.path}');

    final existeEntrada = await imagenOriginal.exists();
    if (!existeEntrada) {
      throw Exception(
        '[_dibujarImpl] Archivo no existe: ${imagenOriginal.path}',
      );
    }

    try {
      // PASO A: Decodificar
      final bytes = await imagenOriginal.readAsBytes();
      final imagen = img.decodeImage(bytes);
      if (imagen == null) throw Exception('img.decodeImage devolvió null');
      debugPrint('🔵 [DibujarA] OK — ${imagen.width}×${imagen.height} px');

      // PASO B: Dibujar — Rama YOLOResult (tiempo real)
      if (yoloResults != null) {
        debugPrint('🔵 [DibujarB] YOLOResult — ${yoloResults.length} items');
        for (int i = 0; i < yoloResults.length; i++) {
          final det = yoloResults[i];
          final box = det.boundingBox;
          final esPxNativos = box.right > 1.5 || box.bottom > 1.5;

          double x1, y1, x2, y2;
          if (esPxNativos) {
            final scaleX = imagen.width / 640.0;
            final scaleY = imagen.height / 640.0;
            x1 = box.left * scaleX;
            y1 = box.top * scaleY;
            x2 = box.right * scaleX;
            y2 = box.bottom * scaleY;
          } else {
            x1 = box.left * imagen.width;
            y1 = box.top * imagen.height;
            x2 = box.right * imagen.width;
            y2 = box.bottom * imagen.height;
          }

          x1 = x1.clamp(0.0, imagen.width.toDouble());
          y1 = y1.clamp(0.0, imagen.height.toDouble());
          x2 = x2.clamp(0.0, imagen.width.toDouble());
          y2 = y2.clamp(0.0, imagen.height.toDouble());

          if (x2 <= x1 + 2 || y2 <= y1 + 2) continue;

          final sev = Constantes.obtenerSeveridadPorClase(det.className);
          final color = _colorPorSeveridad(sev);
          final label =
              '${Constantes.obtenerNombreLegible(det.className)} '
              '${(det.confidence * 100).toStringAsFixed(0)}%';

          _dibujarCuadro(
            imagen,
            x1.toInt(),
            y1.toInt(),
            x2.toInt(),
            y2.toInt(),
            color,
          );
          _dibujarTexto(imagen, label, x1.toInt(), y1.toInt(), color);
          debugPrint('✅ [YOLO $i] $label');
        }
      }

      // PASO B: Dibujar — Rama Map (análisis estático TFLite)
      if (mapResults != null) {
        debugPrint('🔵 [DibujarB] Map (TFLite) — ${mapResults.length} items');
        for (int i = 0; i < mapResults.length; i++) {
          final det = mapResults[i];
          final boxRaw = det['box'];
          final tag = det['tag'] as String? ?? det['fase'] as String;
          final conf =
              det['confidence'] as double? ?? det['confianza'] as double;

          if (boxRaw == null) continue;
          final box = (boxRaw as List).cast<double>();

          final esPxDirectos = box[2] > 1.5 || box[3] > 1.5;
          double x1, y1, x2, y2;
          if (esPxDirectos) {
            x1 = box[0];
            y1 = box[1];
            x2 = box[2];
            y2 = box[3];
          } else {
            x1 = box[0] * imagen.width;
            y1 = box[1] * imagen.height;
            x2 = box[2] * imagen.width;
            y2 = box[3] * imagen.height;
          }

          x1 = x1.clamp(0.0, imagen.width.toDouble());
          y1 = y1.clamp(0.0, imagen.height.toDouble());
          x2 = x2.clamp(0.0, imagen.width.toDouble());
          y2 = y2.clamp(0.0, imagen.height.toDouble());

          if (x2 <= x1 + 2 || y2 <= y1 + 2) continue;

          final sev = Constantes.obtenerSeveridadPorClase(tag);
          final color = _colorPorSeveridad(sev);
          final label =
              '${Constantes.obtenerNombreLegible(tag)} '
              '${(conf * 100).toStringAsFixed(0)}%';

          _dibujarCuadro(
            imagen,
            x1.toInt(),
            y1.toInt(),
            x2.toInt(),
            y2.toInt(),
            color,
          );
          _dibujarTexto(imagen, label, x1.toInt(), y1.toInt(), color);
          debugPrint('✅ [Map $i] $label sev=$sev');
        }
      }

      // PASO C: Guardar imagen anotada
      final dir = await getTemporaryDirectory();
      final ruta =
          '${dir.path}/anotada_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final archivo = File(ruta);
      final jpgBytes = img.encodeJpg(imagen, quality: 92);
      await archivo.writeAsBytes(jpgBytes);

      final tamSalida = await archivo.length();
      if (tamSalida < 100) throw Exception('Archivo de salida inválido');

      debugPrint('✅ [_dibujarImpl] ÉXITO — $ruta ($tamSalida bytes)');
      return archivo;
    } catch (e, stack) {
      debugPrint('❌ [_dibujarImpl] FALLO: $e\n$stack');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS DE DIBUJO
  // ═══════════════════════════════════════════════════════
  void _dibujarCuadro(
    img.Image im,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
  ) {
    img.drawRect(
      im,
      x1: (x1 - 3).clamp(0, im.width - 1),
      y1: (y1 - 3).clamp(0, im.height - 1),
      x2: (x2 + 3).clamp(0, im.width - 1),
      y2: (y2 + 3).clamp(0, im.height - 1),
      color: img.ColorRgb8(0, 0, 0),
      thickness: 10,
    );
    img.drawRect(
      im,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      color: color,
      thickness: 8,
    );
  }

  void _dibujarTexto(
    img.Image im,
    String texto,
    int x,
    int y,
    img.Color color,
  ) {
    final anchoTexto = texto.length * 22 + 40;
    const altoTexto = 70;
    final xT = x.clamp(0, (im.width - anchoTexto).clamp(0, im.width));
    final yT = (y - altoTexto).clamp(
      0,
      (im.height - altoTexto).clamp(0, im.height),
    );

    img.fillRect(
      im,
      x1: xT,
      y1: yT,
      x2: (xT + anchoTexto).clamp(0, im.width - 1),
      y2: (yT + altoTexto).clamp(0, im.height - 1),
      color: img.ColorRgb8(0, 0, 0),
    );
    img.drawRect(
      im,
      x1: xT,
      y1: yT,
      x2: (xT + anchoTexto).clamp(0, im.width - 1),
      y2: (yT + altoTexto).clamp(0, im.height - 1),
      color: color,
      thickness: 5,
    );
    for (int ox = -1; ox <= 1; ox++) {
      for (int oy = -1; oy <= 1; oy++) {
        if (ox != 0 || oy != 0) {
          img.drawString(
            im,
            texto,
            font: img.arial48,
            x: xT + 16 + ox,
            y: yT + 12 + oy,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    img.drawString(
      im,
      texto,
      font: img.arial48,
      x: xT + 16,
      y: yT + 12,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  img.Color _colorPorSeveridad(int sev) {
    switch (sev) {
      case 0:
        return img.ColorRgb8(0, 200, 83);
      case 1:
        return img.ColorRgb8(255, 214, 0);
      case 2:
        return img.ColorRgb8(255, 109, 0);
      case 3:
        return img.ColorRgb8(213, 0, 0);
      default:
        return img.ColorRgb8(255, 255, 255);
    }
  }

  // ═══════════════════════════════════════════════════════
  // CERRAR MODELO
  // ═══════════════════════════════════════════════════════
  Future<void> cerrarModelo() async {
    debugPrint('🔄 [ServicioIA] Cerrando modelo...');
    try {
      _interpreter?.close();
      _interpreter = null;
      _modeloCargado = false;
      debugPrint('✅ [ServicioIA] Modelo cerrado');
    } catch (e) {
      debugPrint('⚠️ [ServicioIA] Error cerrando: $e');
    }
  }
}

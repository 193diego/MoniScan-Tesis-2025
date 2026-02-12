// lib/logica/servicios/servicio_ia.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/constantes.dart';

/// Servicio de IA para detección de Moniliasis con YOLO26
class ServicioIA {
  static Interpreter? _interpreter;
  bool _modeloCargado = false;

  bool get modeloCargado => _modeloCargado;

  // ═══════════════════════════════════════════════════════
  // CARGAR MODELO
  // ═══════════════════════════════════════════════════════
  Future<void> cargarModelo() async {
    if (_modeloCargado && _interpreter != null) {
      debugPrint('✅ Modelo ya cargado');
      return;
    }

    try {
      debugPrint('🔄 Cargando modelo TFLite...');
      _interpreter = await Interpreter.fromAsset(
        Constantes.rutaModelo,
        options: InterpreterOptions()..threads = 4,
      );
      _modeloCargado = true;
      debugPrint('✅ Modelo cargado');
    } catch (e) {
      debugPrint('❌ Error cargando modelo: $e');
      _modeloCargado = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // DETECTAR EN IMAGEN (PARA SUBIR IMAGEN / DIAGNÓSTICO)
  // ═══════════════════════════════════════════════════════
  Future<List<Map<String, dynamic>>> detectarEnImagen({
    required File archivo,
  }) async {
    debugPrint('🔍 Detectando en imagen: ${archivo.path}');

    if (!_modeloCargado || _interpreter == null) {
      await cargarModelo();
    }

    try {
      final bytes = await archivo.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      final resized = img.copyResize(image, width: 640, height: 640);
      final inputBytes = _imageToByteListFloat32(resized, 640, 640);
      final input = inputBytes.reshape([1, 640, 640, 3]);

      final output = List.generate(
        1,
        (_) => List.generate(300, (_) => List<double>.filled(6, 0)),
      );

      _interpreter!.run(input, output);

      final detecciones = _postProcess(output[0], image.width, image.height);

      debugPrint('📊 ${detecciones.length} detecciones encontradas');
      return detecciones;
    } catch (e, stackTrace) {
      debugPrint('❌ Error en detección: $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  Float32List _imageToByteListFloat32(
    img.Image image,
    int inputWidth,
    int inputHeight,
  ) {
    final convertedBytes = Float32List(1 * inputHeight * inputWidth * 3);
    int pixelIndex = 0;

    for (int i = 0; i < inputHeight; i++) {
      for (int j = 0; j < inputWidth; j++) {
        final pixel = image.getPixel(j, i);
        convertedBytes[pixelIndex++] = pixel.r / 255.0;
        convertedBytes[pixelIndex++] = pixel.g / 255.0;
        convertedBytes[pixelIndex++] = pixel.b / 255.0;
      }
    }

    return convertedBytes;
  }

  List<Map<String, dynamic>> _postProcess(
    List<List<double>> output,
    int originalWidth,
    int originalHeight,
  ) {
    final detecciones = <Map<String, dynamic>>[];

    for (final detection in output) {
      final x = detection[0];
      final y = detection[1];
      final w = detection[2];
      final h = detection[3];
      final confidence = detection[4];
      final classId = detection[5].toInt();

      if (confidence < Constantes.umbralConfianza) continue;
      if (classId < 0 || classId >= Constantes.nombresClases.length) continue;

      final className = Constantes.nombresClases[classId];
      final scaleX = originalWidth / 640.0;
      final scaleY = originalHeight / 640.0;

      final x1 = (x - w / 2) * scaleX;
      final y1 = (y - h / 2) * scaleY;
      final x2 = (x + w / 2) * scaleX;
      final y2 = (y + h / 2) * scaleY;

      if (x1 >= x2 || y1 >= y2) continue;

      final severidad = Constantes.obtenerSeveridadPorClase(className);
      final colorSemaforo = Constantes.obtenerColorSemaforo(severidad);

      detecciones.add({
        'tag': className,
        'confidence': confidence,
        'fase': className,
        'confianza': confidence,
        'severidad': severidad,
        'colorSemaforo': colorSemaforo,
        'box': [x1, y1, x2, y2],
      });
    }

    return _applyNMS(detecciones);
  }

  List<Map<String, dynamic>> _applyNMS(List<Map<String, dynamic>> boxes) {
    if (boxes.isEmpty) return [];

    boxes.sort((a, b) {
      final confA = a['confianza'] as double;
      final confB = b['confianza'] as double;
      return confB.compareTo(confA);
    });

    final selected = <Map<String, dynamic>>[];
    final suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      selected.add(boxes[i]);

      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        final iou = _calculateIoU(boxes[i]['box'], boxes[j]['box']);
        if (iou > Constantes.umbralIoU) {
          suppressed[j] = true;
        }
      }
    }

    return selected;
  }

  double _calculateIoU(List<dynamic> box1, List<dynamic> box2) {
    final x1 = box1[0] as double;
    final y1 = box1[1] as double;
    final x2 = box1[2] as double;
    final y2 = box1[3] as double;

    final x1b = box2[0] as double;
    final y1b = box2[1] as double;
    final x2b = box2[2] as double;
    final y2b = box2[3] as double;

    final xi1 = x1 > x1b ? x1 : x1b;
    final yi1 = y1 > y1b ? y1 : y1b;
    final xi2 = x2 < x2b ? x2 : x2b;
    final yi2 = y2 < y2b ? y2 : y2b;

    final interArea =
        (xi2 - xi1).clamp(0, double.infinity) *
        (yi2 - yi1).clamp(0, double.infinity);

    final box1Area = (x2 - x1) * (y2 - y1);
    final box2Area = (x2b - x1b) * (y2b - y1b);
    final unionArea = box1Area + box2Area - interArea;

    return interArea / unionArea;
  }

  // ═══════════════════════════════════════════════════════
  // PROCESAR RESULTADOS YOLO (TIEMPO REAL)
  // ═══════════════════════════════════════════════════════
  List<Map<String, dynamic>> procesarResultadosYOLO(List<YOLOResult> results) {
    final detecciones = <Map<String, dynamic>>[];

    for (final result in results) {
      try {
        if (!Constantes.nombresClases.contains(result.className)) continue;
        if (result.confidence < Constantes.umbralConfianza) continue;

        final severidad = Constantes.obtenerSeveridadPorClase(result.className);
        final colorSemaforo = Constantes.obtenerColorSemaforo(severidad);

        detecciones.add({
          'fase': result.className,
          'confianza': result.confidence,
          'severidad': severidad,
          'colorSemaforo': colorSemaforo,
          'box': [
            result.boundingBox.left,
            result.boundingBox.top,
            result.boundingBox.right,
            result.boundingBox.bottom,
          ],
        });
      } catch (e) {
        debugPrint('❌ Error procesando resultado: $e');
      }
    }
    return detecciones;
  }

  // ═══════════════════════════════════════════════════════
  // PROCESAR DETECCIÓN INDIVIDUAL
  // ═══════════════════════════════════════════════════════
  Map<String, dynamic> procesarDeteccion(Map<String, dynamic> deteccion) {
    final fase = deteccion['fase'] as String? ?? deteccion['tag'] as String;
    final confianza =
        deteccion['confianza'] as double? ?? deteccion['confidence'] as double;
    final severidad = Constantes.obtenerSeveridadPorClase(fase);
    final colorSemaforo = Constantes.obtenerColorSemaforo(severidad);

    return {
      'fase': fase,
      'confianza': confianza,
      'severidad': severidad,
      'colorSemaforo': colorSemaforo,
    };
  }

  // ═══════════════════════════════════════════════════════
  // DIBUJAR ANOTACIONES EN IMAGEN (YOLO RESULTS)
  // ═══════════════════════════════════════════════════════
  Future<File> dibujarAnotacionesEnImagen({
    required File imagenOriginal,
    required List<YOLOResult> detecciones,
  }) async {
    try {
      debugPrint('🎨 Dibujando ${detecciones.length} anotaciones...');

      final bytes = await imagenOriginal.readAsBytes();
      final imagen = img.decodeImage(bytes);

      if (imagen == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      for (final deteccion in detecciones) {
        final box = deteccion.boundingBox;
        final className = deteccion.className;
        final confidence = deteccion.confidence;

        final x1 = box.left.toInt().clamp(0, imagen.width - 1);
        final y1 = box.top.toInt().clamp(0, imagen.height - 1);
        final x2 = box.right.toInt().clamp(0, imagen.width - 1);
        final y2 = box.bottom.toInt().clamp(0, imagen.height - 1);

        if (x2 <= x1 || y2 <= y1) continue;

        final severidad = Constantes.obtenerSeveridadPorClase(className);
        final color = _colorPorSeveridad(severidad);

        img.drawRect(
          imagen,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: color,
          thickness: 4,
        );

        final nombreClase = Constantes.obtenerNombreClase(className);
        final porcentaje = '${(confidence * 100).toStringAsFixed(0)}%';
        _dibujarTexto(imagen, '$nombreClase $porcentaje', x1, y1 - 30, color);
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ruta = '${dir.path}/anotada_$timestamp.jpg';
      final archivo = File(ruta);

      await archivo.writeAsBytes(img.encodeJpg(imagen, quality: 95));

      debugPrint('✅ Imagen anotada: $ruta');
      return archivo;
    } catch (e, stackTrace) {
      debugPrint('❌ Error dibujando: $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════
  // DIBUJAR ANOTACIONES EN IMAGEN (MAP)
  // ═══════════════════════════════════════════════════════
  Future<File> dibujarAnotacionesEnImagenMap({
    required File imagenOriginal,
    required List<Map<String, dynamic>> detecciones,
  }) async {
    try {
      debugPrint('🎨 Dibujando ${detecciones.length} anotaciones...');

      final bytes = await imagenOriginal.readAsBytes();
      final imagen = img.decodeImage(bytes);

      if (imagen == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      for (final deteccion in detecciones) {
        final box = (deteccion['box'] as List).cast<double>();
        final tag = deteccion['tag'] as String? ?? deteccion['fase'] as String;
        final confianza =
            deteccion['confidence'] as double? ??
            deteccion['confianza'] as double;

        final x1 = box[0].toInt().clamp(0, imagen.width - 1);
        final y1 = box[1].toInt().clamp(0, imagen.height - 1);
        final x2 = box[2].toInt().clamp(0, imagen.width - 1);
        final y2 = box[3].toInt().clamp(0, imagen.height - 1);

        if (x2 <= x1 || y2 <= y1) continue;

        final severidad = Constantes.obtenerSeveridadPorClase(tag);
        final color = _colorPorSeveridad(severidad);

        img.drawRect(
          imagen,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          color: color,
          thickness: 4,
        );

        final nombreClase = Constantes.obtenerNombreClase(tag);
        final porcentaje = '${(confianza * 100).toStringAsFixed(0)}%';
        _dibujarTexto(imagen, '$nombreClase $porcentaje', x1, y1 - 30, color);
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ruta = '${dir.path}/anotada_$timestamp.jpg';
      final archivo = File(ruta);

      await archivo.writeAsBytes(img.encodeJpg(imagen, quality: 95));

      debugPrint('✅ Imagen anotada: $ruta');
      return archivo;
    } catch (e, stackTrace) {
      debugPrint('❌ Error dibujando: $e');
      debugPrint('StackTrace: $stackTrace');
      rethrow;
    }
  }

  img.Color _colorPorSeveridad(int severidad) {
    switch (severidad) {
      case 0:
        return img.ColorRgb8(76, 175, 80);
      case 1:
        return img.ColorRgb8(255, 193, 7);
      case 2:
        return img.ColorRgb8(255, 152, 0);
      case 3:
        return img.ColorRgb8(244, 67, 54);
      default:
        return img.ColorRgb8(158, 158, 158);
    }
  }

  void _dibujarTexto(
    img.Image imagen,
    String texto,
    int x,
    int y,
    img.Color color,
  ) {
    final anchoTexto = texto.length * 9 + 12;
    const altoTexto = 24;

    final xT = x.clamp(0, imagen.width - anchoTexto);
    final yT = y.clamp(5, imagen.height - altoTexto);

    img.fillRect(
      imagen,
      x1: xT,
      y1: yT,
      x2: xT + anchoTexto,
      y2: yT + altoTexto,
      color: img.ColorRgb8(0, 0, 0),
    );

    img.drawRect(
      imagen,
      x1: xT,
      y1: yT,
      x2: xT + anchoTexto,
      y2: yT + altoTexto,
      color: color,
      thickness: 2,
    );

    img.drawString(
      imagen,
      texto,
      font: img.arial14,
      x: xT + 6,
      y: yT + 5,
      color: img.ColorRgb8(255, 255, 255),
    );
  }

  Future<void> cerrarModelo() async {
    try {
      _interpreter?.close();
      _interpreter = null;
      _modeloCargado = false;
      debugPrint('✅ Modelo cerrado');
    } catch (e) {
      debugPrint('⚠️ Error cerrando: $e');
    }
  }
}

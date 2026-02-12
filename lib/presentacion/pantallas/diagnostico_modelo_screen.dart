// lib/presentacion/pantallas/diagnostico_modelo_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../logica/servicios/servicio_ia.dart';
import '../../config/tema.dart';

class DiagnosticoModeloScreen extends StatefulWidget {
  const DiagnosticoModeloScreen({super.key});

  @override
  State<DiagnosticoModeloScreen> createState() =>
      _DiagnosticoModeloScreenState();
}

class _DiagnosticoModeloScreenState extends State<DiagnosticoModeloScreen> {
  final ServicioIA _servicioIA = ServicioIA();

  File? _imagenOriginal;
  File? _imagenAnotada;
  List<Map<String, dynamic>>? _detecciones;
  bool _cargando = false;
  bool _modeloCargado = false;

  @override
  void initState() {
    super.initState();
    _cargarModelo();
  }

  Future<void> _cargarModelo() async {
    try {
      await _servicioIA.cargarModelo();
      setState(() => _modeloCargado = true);
    } catch (e) {
      debugPrint('Error cargando modelo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando modelo: $e')));
      }
    }
  }

  Future<void> _seleccionarYDiagnosticar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? imagen = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (imagen == null) return;

    setState(() {
      _cargando = true;
      _imagenOriginal = null;
      _imagenAnotada = null;
      _detecciones = null;
    });

    try {
      final imagenFile = File(imagen.path);
      setState(() => _imagenOriginal = imagenFile);

      // Detectar en imagen
      final resultados = await _servicioIA.detectarEnImagen(
        archivo: imagenFile,
      );

      setState(() => _detecciones = resultados);

      if (resultados.isNotEmpty) {
        // ═══════════════════════════════════════════════════════
        // CORREGIDO: Usar dibujarAnotacionesEnImagenMap para List<Map>
        // ═══════════════════════════════════════════════════════
        final imagenConAnotaciones = await _servicioIA
            .dibujarAnotacionesEnImagenMap(
              imagenOriginal: imagenFile,
              detecciones: resultados,
            );

        setState(() => _imagenAnotada = imagenConAnotaciones);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se detectaron mazorcas en la imagen'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico del Modelo'),
        backgroundColor: TemaApp.verdePrimario,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.biotech, size: 64, color: TemaApp.verdePrimario),
                    const SizedBox(height: 16),
                    Text(
                      _modeloCargado
                          ? 'Modelo YOLO26 cargado'
                          : 'Cargando modelo...',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _cargando || !_modeloCargado
                          ? null
                          : _seleccionarYDiagnosticar,
                      icon: const Icon(Icons.image_search),
                      label: const Text('Probar con Imagen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TemaApp.verdePrimario,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_cargando)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Procesando imagen...'),
                    ],
                  ),
                ),
              ),
            if (_imagenOriginal != null && !_cargando) ...[
              Card(
                elevation: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_imagenAnotada != null) ...[
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Imagen con Anotaciones',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(_imagenAnotada!, fit: BoxFit.contain),
                      ),
                    ] else ...[
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Imagen Original',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          _imagenOriginal!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resultados del Diagnóstico',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: TemaApp.verdePrimario,
                        ),
                      ),
                      const Divider(),
                      if (_detecciones == null || _detecciones!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'No se detectaron mazorcas',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._detecciones!.map((deteccion) {
                          final deteccionData = _servicioIA.procesarDeteccion(
                            deteccion,
                          );
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  deteccionData['colorSemaforo'] == 'verde'
                                  ? TemaApp.verdeSecundario
                                  : deteccionData['colorSemaforo'] == 'amarillo'
                                  ? TemaApp.colorAdvertencia
                                  : Colors.orange,
                              child: const Icon(Icons.eco, color: Colors.white),
                            ),
                            title: Text(deteccionData['fase']),
                            subtitle: Text(
                              'Confianza: ${(deteccionData['confianza'] * 100).toStringAsFixed(1)}%',
                            ),
                            trailing: Chip(
                              label: Text(
                                'Severidad: ${deteccionData['severidad']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor:
                                  deteccionData['colorSemaforo'] == 'verde'
                                  ? TemaApp.verdeSecundario.withValues(
                                      alpha: 0.3,
                                    )
                                  : deteccionData['colorSemaforo'] == 'amarillo'
                                  ? TemaApp.colorAdvertencia.withValues(
                                      alpha: 0.3,
                                    )
                                  : Colors.orange.withValues(alpha: 0.3),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _servicioIA.cerrarModelo();
    super.dispose();
  }
}

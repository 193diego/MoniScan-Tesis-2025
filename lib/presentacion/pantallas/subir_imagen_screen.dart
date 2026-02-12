// lib/presentacion/pantallas/subir_imagen_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../logica/servicios/servicio_ia.dart';
import '../../logica/servicios/servicio_gps.dart';
import '../../logica/servicios/servicio_sincronizacion.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';
import 'detalle_deteccion_screen.dart';

class SubirImagenScreen extends StatefulWidget {
  final String cedulaUsuario;
  const SubirImagenScreen({super.key, required this.cedulaUsuario});

  @override
  State<SubirImagenScreen> createState() => _SubirImagenScreenState();
}

class _SubirImagenScreenState extends State<SubirImagenScreen> {
  final ServicioIA _servicioIA = ServicioIA();
  final ServicioGPS _servicioGPS = ServicioGPS();
  final BaseDatosHelper _bd = BaseDatosHelper();
  final ServicioSincronizacion _sincronizacion = ServicioSincronizacion();

  File? _imagen;
  File? _imagenConAnotaciones;
  List<Map<String, dynamic>>? _resultados;
  bool _cargando = false;
  bool _analizando = false;
  bool _modeloCargado = false;

  @override
  void initState() {
    super.initState();
    _cargarModelo();
  }

  Future<void> _cargarModelo() async {
    try {
      debugPrint('🔄 SubirImagen: Cargando modelo FlutterVision...');
      await _servicioIA.cargarModelo();
      if (mounted) {
        setState(() => _modeloCargado = true);
        debugPrint('✅ SubirImagen: Modelo FlutterVision cargado');
      }
    } catch (e) {
      debugPrint('❌ SubirImagen: Error cargando modelo: $e');
      if (mounted) {
        _mostrarMensaje('Error cargando modelo: $e');
      }
    }
  }

  Future<void> _seleccionarYAnalizar() async {
    if (!_modeloCargado) {
      _mostrarMensaje('El modelo aún no está cargado. Espera un momento...');
      return;
    }

    final ImagePicker picker = ImagePicker();

    try {
      final XFile? imagen = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (imagen == null) {
        debugPrint('ℹ️ SubirImagen: Usuario canceló selección');
        return;
      }

      debugPrint('📸 SubirImagen: Imagen seleccionada: ${imagen.path}');

      setState(() {
        _cargando = true;
        _imagen = null;
        _imagenConAnotaciones = null;
        _resultados = null;
      });

      // Validar que la imagen se puede decodificar
      try {
        final bytes = await imagen.readAsBytes();
        await decodeImageFromList(bytes);
        debugPrint('✅ SubirImagen: Imagen decodificada correctamente');
      } catch (e) {
        throw Exception('No se pudo decodificar la imagen: $e');
      }

      setState(() {
        _imagen = File(imagen.path);
        _analizando = true;
      });

      debugPrint('🔍 SubirImagen: Iniciando análisis con FlutterVision...');

      // Ejecutar detección con FlutterVision
      final resultados = await _servicioIA.detectarEnImagen(
        archivo: File(imagen.path),
      );

      debugPrint(
        '📊 SubirImagen: Resultados: ${resultados.length} detecciones',
      );

      // Si hay detecciones, dibujar anotaciones
      if (resultados.isNotEmpty) {
        debugPrint('🎨 SubirImagen: Dibujando anotaciones...');

        final imagenAnotada = await _servicioIA.dibujarAnotacionesEnImagenMap(
          imagenOriginal: File(imagen.path),
          detecciones: resultados,
        );

        setState(() {
          _imagenConAnotaciones = imagenAnotada;
        });

        debugPrint('✅ SubirImagen: Anotaciones dibujadas');
      } else {
        debugPrint('⚠️ SubirImagen: No se detectaron mazorcas');
      }

      setState(() {
        _resultados = resultados;
        _analizando = false;
      });

      if (resultados.isEmpty) {
        _mostrarMensaje('No se detectaron mazorcas en la imagen');
      } else {
        _mostrarMensaje('✅ Se detectaron ${resultados.length} mazorca(s)');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ SubirImagen: Error al procesar imagen: $e');
      debugPrint('StackTrace: $stackTrace');
      _mostrarMensaje('Error al procesar imagen: $e');
      setState(() {
        _analizando = false;
        _cargando = false;
      });
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _guardarDeteccion() async {
    if (_resultados == null ||
        _resultados!.isEmpty ||
        _imagenConAnotaciones == null) {
      _mostrarMensaje('No hay detecciones para guardar');
      return;
    }

    _mostrarDialogoCarga('Guardando detección...');

    try {
      debugPrint('📍 SubirImagen: Obteniendo ubicación...');
      final coordenadas = await _servicioGPS.obtenerCoordenadas();
      final direccion = await _servicioGPS.obtenerDireccion(
        coordenadas['latitud']!,
        coordenadas['longitud']!,
      );

      final grupoImagen = const Uuid().v4().substring(0, 8);
      final userAuth = FirebaseAuth.instance.currentUser;

      debugPrint(
        '💾 SubirImagen: Guardando ${_resultados!.length} detección(es)...',
      );

      for (var resultado in _resultados!) {
        final deteccionData = _servicioIA.procesarDeteccion(resultado);

        final deteccion = Deteccion(
          id: null,
          idMazorca: const Uuid().v4(),
          grupoImagen: grupoImagen,
          idUsuario: widget.cedulaUsuario,
          workerId: userAuth?.uid,
          fase: deteccionData['fase'],
          confianza: deteccionData['confianza'],
          severidad: deteccionData['severidad'],
          colorSemaforo: deteccionData['colorSemaforo'],
          rutaImagen: _imagenConAnotaciones!.path,
          fecha: DateTime.now(),
          latitud: coordenadas['latitud']!,
          longitud: coordenadas['longitud']!,
          direccion: direccion,
          lote: null,
          notas: 'Imagen subida desde galería',
          sincronizado: false,
        );

        await _bd.insertarDeteccion(deteccion);
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      // Intentar sincronizar
      if (userAuth != null) {
        debugPrint('☁️ SubirImagen: Sincronizando con Firebase...');
        try {
          await _sincronizacion.sincronizarTodo();
          _mostrarMensaje('✅ Detección guardada y sincronizada');
        } catch (e) {
          debugPrint('⚠️ SubirImagen: Error en sincronización: $e');
          _mostrarMensaje('✅ Detección guardada. Se sincronizará después');
        }
      } else {
        _mostrarMensaje('✅ Detección guardada localmente');
      }

      // Navegar a detalle
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
      debugPrint('❌ SubirImagen: Error guardando: $e');
      debugPrint('StackTrace: $stackTrace');

      if (mounted) Navigator.of(context).pop();
      _mostrarMensaje('Error al guardar: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subir Imagen'),
        backgroundColor: TemaApp.verdePrimario,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card de selección
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 64,
                      color: TemaApp.verdePrimario,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _modeloCargado
                          ? 'Selecciona una imagen de tu galería'
                          : 'Cargando modelo FlutterVision...',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!_modeloCargado)
                      const CircularProgressIndicator()
                    else
                      ElevatedButton.icon(
                        onPressed: _cargando ? null : _seleccionarYAnalizar,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Seleccionar Imagen'),
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

            // Loading de análisis
            if (_analizando)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Analizando imagen con FlutterVision...',
                        style: TextStyle(color: TemaApp.verdePrimario),
                      ),
                    ],
                  ),
                ),
              ),

            // Resultados
            if (_imagen != null && !_analizando) ...[
              Card(
                elevation: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Imagen con anotaciones
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      child: Image.file(
                        _imagenConAnotaciones ?? _imagen!,
                        fit: BoxFit.contain,
                      ),
                    ),

                    // Lista de resultados
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.analytics,
                                color: TemaApp.verdePrimario,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Resultados del análisis:',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: TemaApp.verdePrimario,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          if (_resultados == null || _resultados!.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'No se detectaron mazorcas en esta imagen',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ..._resultados!.asMap().entries.map((entry) {
                              final index = entry.key;
                              final resultado = entry.value;
                              final deteccionData = _servicioIA
                                  .procesarDeteccion(resultado);

                              Color color;
                              switch (deteccionData['colorSemaforo']) {
                                case 'verde':
                                  color = TemaApp.verdeSecundario;
                                  break;
                                case 'amarillo':
                                  color = TemaApp.colorAdvertencia;
                                  break;
                                case 'naranja':
                                  color = Colors.orange;
                                  break;
                                case 'rojo':
                                  color = Colors.red;
                                  break;
                                default:
                                  color = Colors.grey;
                              }

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 1,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: color,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    Constantes.obtenerNombreClase(
                                      deteccionData['fase'],
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Confianza: ${(deteccionData['confianza'] * 100).toStringAsFixed(1)}%',
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      deteccionData['colorSemaforo']
                                          .toString()
                                          .toUpperCase(),
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Botón de guardar
              if (_resultados != null && _resultados!.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _guardarDeteccion,
                  icon: const Icon(Icons.save),
                  label: Text(
                    'Guardar ${_resultados!.length} Detección${_resultados!.length > 1 ? 'es' : ''}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemaApp.verdePrimario,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// lib/presentacion/pantallas/subir_imagen_screen.dart
// ✅ VERSIÓN FINAL COMPLETA CON TRATAMIENTO MEJORADO
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
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
  // Opcionales: cuando viene desde historial para dar seguimiento
  final String? grupoImagenSeguimiento;
  final String? idMazorcaSeguimiento;

  const SubirImagenScreen({
    super.key,
    required this.cedulaUsuario,
    this.grupoImagenSeguimiento,
    this.idMazorcaSeguimiento,
  });

  @override
  State<SubirImagenScreen> createState() => _SubirImagenScreenState();
}

class _SubirImagenScreenState extends State<SubirImagenScreen> {
  final ServicioIA _servicioIA = ServicioIA();
  final ServicioGPS _servicioGPS = ServicioGPS();
  final BaseDatosHelper _bd = BaseDatosHelper();
  final ServicioSincronizacion _sincronizacion = ServicioSincronizacion();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      debugPrint('🔄 SubirImagen: Cargando modelo...');
      await _servicioIA.cargarModelo();
      if (mounted) {
        setState(() => _modeloCargado = true);
        debugPrint('✅ SubirImagen: Modelo cargado exitosamente');
      }
    } catch (e) {
      debugPrint('❌ SubirImagen: Error cargando modelo: $e');
      if (mounted) _mostrarMensaje('Error cargando modelo: $e');
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
        _imagenConAnotaciones = null;
        _resultados = null;
      });

      try {
        final bytes = await imagen.readAsBytes();
        await decodeImageFromList(bytes);
        debugPrint('✅ SubirImagen: Imagen decodificada correctamente');
      } catch (e) {
        throw Exception('No se pudo decodificar la imagen: $e');
      }

      setState(() => _analizando = true);

      debugPrint('🔍 SubirImagen: Iniciando análisis con TFLite...');

      final resultados = await _servicioIA.detectarEnImagen(
        archivo: File(imagen.path),
      );

      debugPrint(
        '📊 SubirImagen: Resultados: ${resultados.length} detecciones',
      );

      debugPrint('🎨 SubirImagen: Dibujando anotaciones...');

      final imagenAnotada = await _servicioIA.dibujarAnotacionesEnImagenMap(
        imagenOriginal: File(imagen.path),
        detecciones: resultados,
      );

      setState(() {
        _imagenConAnotaciones = imagenAnotada;
        _resultados = resultados;
        _analizando = false;
      });

      debugPrint('✅ SubirImagen: Anotaciones dibujadas');

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
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarDeteccion() async {
    if (_resultados == null || _resultados!.isEmpty) {
      _mostrarMensaje('No hay detecciones para guardar');
      return;
    }

    if (_imagenConAnotaciones == null) {
      _mostrarMensaje('No se ha generado la imagen anotada');
      return;
    }

    // ✅ PASO 1: MOSTRAR DIÁLOGO PARA SELECCIONAR LOTE Y OBSERVACIONES
    final datosAdicionales = await _mostrarDialogoLoteYObservaciones();

    if (datosAdicionales == null) {
      debugPrint('ℹ️ Usuario canceló el guardado');
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

      // En modo seguimiento usamos los IDs existentes para asociar al registro
      final bool esSeguimiento = widget.grupoImagenSeguimiento != null;
      final grupoImagen = esSeguimiento
          ? widget.grupoImagenSeguimiento!
          : const Uuid().v4().substring(0, 8);
      final userAuth = FirebaseAuth.instance.currentUser;

      if (userAuth == null) {
        throw Exception('Usuario no autenticado. Inicia sesión primero.');
      }

      debugPrint(
        '💾 SubirImagen: Guardando ${_resultados!.length} detección(es)...',
      );

      // ✅ CREAR TODAS LAS DETECCIONES
      final deteccionesCreadas = <Deteccion>[];

      for (var resultado in _resultados!) {
        final deteccionData = _servicioIA.procesarDeteccion(resultado);

        final deteccion = Deteccion(
          id: null,
          idMazorca: esSeguimiento
              ? (widget.idMazorcaSeguimiento ?? const Uuid().v4())
              : const Uuid().v4(),
          grupoImagen: grupoImagen,
          idUsuario: widget.cedulaUsuario,
          workerId: userAuth.uid,
          fase: deteccionData['fase'],
          confianza: deteccionData['confianza'],
          severidad: deteccionData['severidad'],
          colorSemaforo: deteccionData['colorSemaforo'],
          rutaImagen: _imagenConAnotaciones!.path,
          fecha: DateTime.now(),
          latitud: coordenadas['latitud']!,
          longitud: coordenadas['longitud']!,
          direccion: direccion,
          lote: datosAdicionales['loteNombre'],
          loteId: datosAdicionales['loteId'],
          notas: datosAdicionales['observaciones'],
          sincronizado: false,
        );

        deteccionesCreadas.add(deteccion);
      }

      // ✅ SUBIR IMAGEN A FIREBASE STORAGE UNA SOLA VEZ
      debugPrint('☁️ Subiendo imagen a Firebase Storage...');

      final imagenUrl = await _sincronizacion.subirImagenPublica(
        archivoLocal: _imagenConAnotaciones!,
        workerId: userAuth.uid,
      );

      debugPrint('✅ Imagen subida: $imagenUrl');

      // ✅ GUARDAR DETECCIONES CON LA URL REAL
      for (var deteccion in deteccionesCreadas) {
        final deteccionConUrl = Deteccion(
          id: deteccion.id,
          idMazorca: deteccion.idMazorca,
          grupoImagen: deteccion.grupoImagen,
          idUsuario: deteccion.idUsuario,
          workerId: deteccion.workerId,
          fase: deteccion.fase,
          confianza: deteccion.confianza,
          severidad: deteccion.severidad,
          colorSemaforo: deteccion.colorSemaforo,
          rutaImagen: imagenUrl,
          fecha: deteccion.fecha,
          latitud: deteccion.latitud,
          longitud: deteccion.longitud,
          direccion: deteccion.direccion,
          lote: deteccion.lote,
          loteId: deteccion.loteId,
          notas: deteccion.notas,
          sincronizado: false,
          enSeguimiento: deteccion.enSeguimiento,
          tratamientoId: deteccion.tratamientoId,
          precisionGPS: deteccion.precisionGPS,
        );

        await _bd.insertarDeteccion(deteccionConUrl);
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      // ✅ MOSTRAR TRATAMIENTO RECOMENDADO
      await _mostrarTratamientoRecomendado(deteccionesCreadas.first.fase);

      // ✅ SINCRONIZAR CON FIRESTORE
      debugPrint('☁️ Sincronizando con Firestore...');
      try {
        await _sincronizacion.sincronizarTodo();
        _mostrarMensaje('✅ Detección guardada y sincronizada');
      } catch (e) {
        debugPrint('⚠️ Error en sincronización: $e');
        _mostrarMensaje('✅ Guardado. Se sincronizará después');
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
      debugPrint('❌ SubirImagen: Error guardando: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) Navigator.of(context).pop();
      _mostrarMensaje('Error al guardar: $e');
    }
  }

  // ✅ DIÁLOGO PARA SELECCIONAR LOTE Y AGREGAR OBSERVACIONES
  Future<Map<String, String>?> _mostrarDialogoLoteYObservaciones() async {
    String? loteSeleccionadoId;
    String? loteSeleccionadoNombre;
    final observacionesController = TextEditingController();

    // Cargar lotes desde Firestore
    List<Map<String, String>> lotes = [];
    try {
      final snapshot = await _firestore
          .collection('lotes')
          .where('activo', isEqualTo: true)
          .get();

      lotes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'nombre': data['nombre'] as String? ?? 'Sin nombre',
        };
      }).toList();

      if (lotes.isEmpty) {
        _mostrarMensaje(
          '⚠️ No hay lotes disponibles. Contacta al administrador.',
        );
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error cargando lotes: $e');
      _mostrarMensaje('Error cargando lotes: $e');
      return null;
    }

    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Información adicional',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lote *',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  hint: const Text('Selecciona un lote'),
                  value: loteSeleccionadoId,
                  items: lotes.map((lote) {
                    return DropdownMenuItem<String>(
                      value: lote['id'],
                      child: Text(lote['nombre']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      loteSeleccionadoId = value;
                      loteSeleccionadoNombre = lotes.firstWhere(
                        (l) => l['id'] == value,
                      )['nombre'];
                    });
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Observaciones',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: observacionesController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hintText: 'Notas adicionales (opcional)',
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  maxLines: 3,
                  maxLength: 500,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (loteSeleccionadoId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Debes seleccionar un lote'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'loteId': loteSeleccionadoId!,
                  'loteNombre': loteSeleccionadoNombre!,
                  'observaciones': observacionesController.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TemaApp.verdePrimario,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );

    return resultado;
  }

  // ✅ MOSTRAR TRATAMIENTO RECOMENDADO MEJORADO
  Future<void> _mostrarTratamientoRecomendado(String fase) async {
    try {
      final tratamiento = await _sincronizacion.obtenerTratamientoRecomendado(
        fase,
      );

      if (!mounted) return;

      // ✅ Si NO hay tratamiento registrado
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
                          'La administradora debe crear este protocolo desde el panel web (sección Tratamientos).',
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

      // ✅ SI HAY tratamiento, mostrarlo completo
      final nombreFase = tratamiento['nombre'] as String? ?? 'Desconocido';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar tratamiento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.grupoImagenSeguimiento != null
              ? 'Seguimiento — Subir Imagen'
              : 'Subir Imagen',
        ),
        backgroundColor: TemaApp.verdePrimario,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_modeloCargado) ...[
              const CircularProgressIndicator(color: TemaApp.verdePrimario),
              const SizedBox(height: 24),
              const Text(
                'Cargando modelo...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ] else if (_analizando) ...[
              const CircularProgressIndicator(color: TemaApp.verdePrimario),
              const SizedBox(height: 24),
              const Text(
                'Analizando imagen...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ] else if (_imagenConAnotaciones != null) ...[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _imagenConAnotaciones!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_resultados != null && _resultados!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: TemaApp.verdeClaro.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: TemaApp.verdeSecundario),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: TemaApp.verdeSecundario,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${_resultados!.length} Detección${_resultados!.length > 1 ? 'es' : ''}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: TemaApp.verdePrimario,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ..._resultados!.map((det) {
                                final fase = det['fase'] as String;
                                final confianza = det['confianza'] as double;
                                final nombreClase =
                                    Constantes.obtenerNombreLegible(fase);
                                final color = Constantes.obtenerColorPorClase(
                                  fase,
                                );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '$nombreClase (${(confianza * 100).toStringAsFixed(0)}%)',
                                          style: const TextStyle(
                                            fontSize: 14,
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
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.orange.shade700,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'No se detectaron mazorcas en la imagen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _imagenConAnotaciones = null;
                          _resultados = null;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Nueva imagen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TemaApp.verdePrimario,
                        side: const BorderSide(color: TemaApp.verdePrimario),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  if (_resultados != null && _resultados!.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _guardarDeteccion,
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TemaApp.verdeSecundario,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ] else ...[
              Icon(
                Icons.cloud_upload_outlined,
                size: 120,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 32),
              const Text(
                'Selecciona una imagen de tu galería',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'El sistema detectará automáticamente las mazorcas',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _cargando ? null : _seleccionarYAnalizar,
                  icon: const Icon(Icons.image, size: 24),
                  label: Text(
                    _cargando ? 'Procesando...' : 'Seleccionar imagen',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemaApp.verdePrimario,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

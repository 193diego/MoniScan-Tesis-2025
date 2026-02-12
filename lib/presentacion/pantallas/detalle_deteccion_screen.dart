// lib/presentacion/pantallas/detalle_deteccion_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';
import 'mapa_screen.dart';

class DetalleDeteccionScreen extends StatefulWidget {
  final String grupoImagen;
  const DetalleDeteccionScreen({super.key, required this.grupoImagen});

  @override
  State<DetalleDeteccionScreen> createState() => _DetalleDeteccionScreenState();
}

class _DetalleDeteccionScreenState extends State<DetalleDeteccionScreen> {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Deteccion> _detecciones = [];
  bool _cargando = true;
  bool _modoOnline = false;

  String? _imagenUrl;
  double? _latitud;
  double? _longitud;

  @override
  void initState() {
    super.initState();
    _cargarDetecciones();
  }

  Future<void> _cargarDetecciones() async {
    setState(() => _cargando = true);

    try {
      final conectividad = await Connectivity().checkConnectivity();
      // CORREGIDO: checkConnectivity() devuelve ConnectivityResult (NO lista)
      final tieneInternet = conectividad != ConnectivityResult.none;

      if (tieneInternet && _modoOnline) {
        final deteccionesFirebase = await _cargarDesdeFirebase();
        if (deteccionesFirebase.isNotEmpty) {
          setState(() {
            _detecciones = deteccionesFirebase;
            _imagenUrl = _detecciones.first.rutaImagen;
            _latitud = _detecciones.first.latitud;
            _longitud = _detecciones.first.longitud;
            _cargando = false;
          });
          return;
        }
      }

      throw Exception('Sin conexión');
    } catch (e) {
      final deteccionesLocales = await _db.obtenerDeteccionesPorGrupo(
        widget.grupoImagen,
      );
      setState(() {
        _detecciones = deteccionesLocales;
        if (_detecciones.isNotEmpty) {
          _imagenUrl = _detecciones.first.rutaImagen;
          _latitud = _detecciones.first.latitud;
          _longitud = _detecciones.first.longitud;
        }
        _modoOnline = false;
        _cargando = false;
      });
    }
  }

  Future<List<Deteccion>> _cargarDesdeFirebase() async {
    final snapshot = await _firestore
        .collection('detecciones')
        .where('grupoImagen', isEqualTo: widget.grupoImagen)
        .get();

    if (snapshot.docs.isEmpty) return [];

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Deteccion(
        idMazorca: data['idMazorca'],
        grupoImagen: data['grupoImagen'],
        idUsuario: data['idUsuario'],
        workerId: data['workerId'],
        fase: data['fase'],
        confianza: (data['confianza'] as num).toDouble(),
        severidad: data['severidad'],
        colorSemaforo: data['colorSemaforo'],
        rutaImagen: data['imagenUrl'],
        latitud: (data['latitud'] as num).toDouble(),
        longitud: (data['longitud'] as num).toDouble(),
        direccion: data['direccion'],
        lote: data['lote'],
        notas: data['notas'],
        fecha: (data['timestamp'] ?? data['fecha']).toDate(),
        sincronizado: true,
      );
    }).toList();
  }

  void _verEnMapa() {
    if (_latitud == null || _longitud == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay ubicación')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapaScreen(
          latitud: _latitud!,
          longitud: _longitud!,
          titulo: 'Ubicación',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        backgroundColor: TemaApp.verdePrimario,
        actions: [
          IconButton(
            icon: Icon(_modoOnline ? Icons.cloud : Icons.cloud_off),
            onPressed: () {
              setState(() => _modoOnline = !_modoOnline);
              _cargarDetecciones();
            },
          ),
        ],
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando...')
          : _detecciones.isEmpty
          ? const Center(child: Text('No hay detecciones'))
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (_imagenUrl != null)
                    _modoOnline && _imagenUrl!.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: _imagenUrl!,
                            height: 250,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(_imagenUrl!),
                            height: 250,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grupo ${widget.grupoImagen.substring(0, 8)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('${_detecciones.length} detecciones'),
                        const SizedBox(height: 16),
                        if (_latitud != null && _longitud != null)
                          ElevatedButton.icon(
                            onPressed: _verEnMapa,
                            icon: const Icon(Icons.map),
                            label: const Text('Ver en Mapa'),
                          ),
                        const SizedBox(height: 24),
                        const Text(
                          'Detecciones',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ...(_detecciones.map((det) {
                          return ListTile(
                            title: Text(det.fase),
                            subtitle: Text(
                              '${(det.confianza * 100).toStringAsFixed(0)}%',
                            ),
                            leading: CircleAvatar(
                              child: Text('${det.severidad}'),
                            ),
                          );
                        })),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

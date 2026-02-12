// lib/presentacion/pantallas/mapa_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';
import 'detalle_deteccion_screen.dart';

class MapaScreen extends StatefulWidget {
  final double? latitud;
  final double? longitud;
  final String? titulo;
  final String? cedulaUsuario;

  const MapaScreen({
    super.key,
    this.latitud,
    this.longitud,
    this.titulo,
    this.cedulaUsuario,
  });

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final BaseDatosHelper _db = BaseDatosHelper();

  GoogleMapController? _mapController;
  Set<Marker> _marcadores = {};
  LatLng? _ubicacionActual;
  bool _cargando = true;
  bool _mostrarLista = false; // NUEVO: Control de lista flotante

  Map<LatLng, List<Deteccion>> _deteccionesPorUbicacion = {};

  @override
  void initState() {
    super.initState();
    _inicializarMapa();
  }

  Future<void> _inicializarMapa() async {
    setState(() => _cargando = true);

    try {
      if (widget.latitud != null && widget.longitud != null) {
        _ubicacionActual = LatLng(widget.latitud!, widget.longitud!);
        _agregarMarcadorEspecifico();
      } else {
        await _cargarDetecciones();
        await _obtenerUbicacionActual();
      }
    } catch (e) {
      debugPrint('❌ Error inicializando mapa: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDetecciones() async {
    if (widget.cedulaUsuario == null) return;

    try {
      final detecciones = await _db.obtenerTodasDetecciones(
        widget.cedulaUsuario!,
      );
      final Map<LatLng, List<Deteccion>> agrupadas = {};

      for (var deteccion in detecciones) {
        if (deteccion.latitud != 0 && deteccion.longitud != 0) {
          final lat = double.parse(deteccion.latitud.toStringAsFixed(5));
          final lng = double.parse(deteccion.longitud.toStringAsFixed(5));
          final ubicacion = LatLng(lat, lng);

          if (!agrupadas.containsKey(ubicacion)) {
            agrupadas[ubicacion] = [];
          }
          agrupadas[ubicacion]!.add(deteccion);
        }
      }

      _deteccionesPorUbicacion = agrupadas;
      _crearMarcadores();
    } catch (e) {
      debugPrint('❌ Error cargando detecciones: $e');
    }
  }

  void _crearMarcadores() {
    final Set<Marker> nuevosMarcadores = {};

    _deteccionesPorUbicacion.forEach((ubicacion, detecciones) {
      final totalDetecciones = detecciones.length;
      final ultimaDeteccion = detecciones.first;

      nuevosMarcadores.add(
        Marker(
          markerId: MarkerId(ubicacion.toString()),
          position: ubicacion,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _getColorMarcador(ultimaDeteccion.colorSemaforo),
          ),
          infoWindow: InfoWindow(
            title:
                '$totalDetecciones ${totalDetecciones == 1 ? 'detección' : 'detecciones'}',
            snippet: ultimaDeteccion.lote ?? 'Sin lote',
            onTap: () => _irAUbicacion(ubicacion),
          ),
        ),
      );
    });

    if (mounted) setState(() => _marcadores = nuevosMarcadores);
  }

  void _agregarMarcadorEspecifico() {
    if (mounted) {
      setState(() {
        _marcadores = {
          Marker(
            markerId: const MarkerId('ubicacion_especifica'),
            position: _ubicacionActual!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(title: widget.titulo ?? 'Ubicación'),
          ),
        };
      });
    }
  }

  Future<void> _obtenerUbicacionActual() async {
    try {
      bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicioHabilitado) return;

      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) return;
      }

      if (permiso == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted && _ubicacionActual == null) {
        setState(
          () =>
              _ubicacionActual = LatLng(position.latitude, position.longitude),
        );
      }

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_ubicacionActual!, 15),
      );
    } catch (e) {
      debugPrint('❌ Error obteniendo ubicación: $e');
    }
  }

  // NUEVO: Ir a ubicación específica
  void _irAUbicacion(LatLng ubicacion) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(ubicacion, 18));
    setState(() => _mostrarLista = false);
  }

  double _getColorMarcador(String colorSemaforo) {
    switch (colorSemaforo.toLowerCase()) {
      case 'verde':
        return BitmapDescriptor.hueGreen;
      case 'amarillo':
        return BitmapDescriptor.hueYellow;
      case 'naranja':
        return BitmapDescriptor.hueOrange;
      case 'rojo':
        return BitmapDescriptor.hueRed;
      default:
        return BitmapDescriptor.hueBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo ?? 'Mapa de Detecciones'),
        backgroundColor: TemaApp.verdePrimario,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _obtenerUbicacionActual,
            tooltip: 'Mi ubicación',
          ),
          if (widget.cedulaUsuario != null)
            IconButton(
              icon: Icon(_mostrarLista ? Icons.map : Icons.list),
              onPressed: () => setState(() => _mostrarLista = !_mostrarLista),
              tooltip: _mostrarLista ? 'Ver mapa' : 'Ver lista',
            ),
        ],
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando mapa...')
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _ubicacionActual ?? const LatLng(-2.1709, -79.9224),
                    zoom: 14,
                  ),
                  markers: _marcadores,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  onMapCreated: (controller) => _mapController = controller,
                ),

                // LEYENDA
                if (widget.cedulaUsuario != null && !_mostrarLista)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Leyenda',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _ItemLeyenda(color: Colors.green, texto: 'Sana'),
                            _ItemLeyenda(
                              color: Colors.yellow[700]!,
                              texto: 'Temprana',
                            ),
                            _ItemLeyenda(
                              color: Colors.orange,
                              texto: 'Intermedia',
                            ),
                            _ItemLeyenda(color: Colors.red, texto: 'Avanzada'),
                          ],
                        ),
                      ),
                    ),
                  ),

                // LISTA FLOTANTE (NUEVO)
                if (_mostrarLista && _deteccionesPorUbicacion.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: TemaApp.verdePrimario,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_deteccionesPorUbicacion.length} ${_deteccionesPorUbicacion.length == 1 ? 'ubicación' : 'ubicaciones'}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _deteccionesPorUbicacion.length,
                              itemBuilder: (context, index) {
                                final ubicacion = _deteccionesPorUbicacion.keys
                                    .elementAt(index);
                                final detecciones =
                                    _deteccionesPorUbicacion[ubicacion]!;

                                return _TarjetaUbicacion(
                                  ubicacion: ubicacion,
                                  detecciones: detecciones,
                                  onTap: () => _irAUbicacion(ubicacion),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // CONTADOR
                if (!_mostrarLista && _deteccionesPorUbicacion.isNotEmpty)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: TemaApp.verdePrimario,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_deteccionesPorUbicacion.length} ${_deteccionesPorUbicacion.length == 1 ? 'ubicación' : 'ubicaciones'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  final Color color;
  final String texto;

  const _ItemLeyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(texto, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// NUEVO: Tarjeta de ubicación en lista
class _TarjetaUbicacion extends StatelessWidget {
  final LatLng ubicacion;
  final List<Deteccion> detecciones;
  final VoidCallback onTap;

  const _TarjetaUbicacion({
    required this.ubicacion,
    required this.detecciones,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primeraDeteccion = detecciones.first;
    final totalDetecciones = detecciones.length;
    final fases = detecciones.map((d) => d.fase).toSet().toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: TemaApp.verdePrimario.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.location_on, color: TemaApp.verdePrimario),
        ),
        title: Text(
          '$totalDetecciones ${totalDetecciones == 1 ? 'detección' : 'detecciones'}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: fases
                  .map((fase) => EtiquetaFase(fase: fase, tamanoTexto: 10))
                  .toList(),
            ),
            if (primeraDeteccion.lote != null) ...[
              const SizedBox(height: 4),
              Text(
                'Lote: ${primeraDeteccion.lote}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.map, color: TemaApp.verdePrimario),
              onPressed: onTap,
              tooltip: 'Ver en mapa',
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetalleDeteccionScreen(
                grupoImagen: primeraDeteccion.grupoImagen!,
              ),
            ),
          );
        },
      ),
    );
  }
}

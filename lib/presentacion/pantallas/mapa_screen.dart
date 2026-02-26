// lib/presentacion/pantallas/mapa_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/tema.dart';
import '../../config/constantes.dart';
import 'detalle_deteccion_screen.dart';

class MapaScreen extends StatefulWidget {
  final String cedulaUsuario;
  const MapaScreen({super.key, required this.cedulaUsuario});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ FIX 1: Usar UID real de Firebase Auth, no la cédula
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  GoogleMapController? _mapController;
  bool _mapControllerDisposed =
      false; // ✅ FIX 2: flag para evitar uso tras dispose

  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _detecciones = [];
  List<Map<String, dynamic>> _deteccionesFiltradas = [];
  Map<String, dynamic>? _deteccionSeleccionada;

  bool _cargando = true;
  bool _mostrarListado = false;
  LatLng _centroInicial = const LatLng(-2.1372167, -79.6070379);

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _listadoController;
  late Animation<Offset> _listadoAnimation;

  String? _faseSeleccionada;
  final List<String> _fasesDisponibles = [
    'SANA',
    'FASE_INICIAL',
    'FASE_INTERMEDIA',
    'FASE_AVANZADA',
  ];

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _listadoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _listadoAnimation =
        Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _listadoController,
            curve: Curves.easeOutCubic,
          ),
        );

    _cargarDetecciones();
    _obtenerUbicacionActual();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _listadoController.dispose();
    // ✅ FIX 2: marcar como disposed ANTES de llamar dispose()
    // para que ningún callback asíncrono use el controller después
    _mapControllerDisposed = true;
    _mapController?.dispose();
    super.dispose();
  }

  // Helper seguro para animar la cámara
  void _animarCamara(CameraUpdate update) {
    if (!_mapControllerDisposed && _mapController != null) {
      _mapController!.animateCamera(update);
    }
  }

  Future<void> _obtenerUbicacionActual() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _centroInicial = LatLng(position.latitude, position.longitude);
      });
      _animarCamara(CameraUpdate.newLatLng(_centroInicial));
    } catch (e) {
      debugPrint('⚠️ No se pudo obtener ubicación: $e');
    }
  }

  Future<void> _cargarDetecciones() async {
    if (!mounted) return;
    setState(() => _cargando = true);

    try {
      debugPrint('🗺️ Cargando mapa para UID: $_uid');

      // ✅ FIX 1: filtrar por trabajadorUID (UID real), no por cédula
      final snapshot = await _firestore
          .collection('detecciones')
          .where('trabajadorUID', isEqualTo: _uid)
          .get();

      debugPrint('🗺️ ${snapshot.docs.length} detecciones encontradas');

      final detecciones = snapshot.docs.map((doc) {
        final data = doc.data();

        DateTime fecha = DateTime.now();
        final fechaRaw = data['fechaDeteccion'] ?? data['creadoEn'];
        if (fechaRaw is Timestamp) fecha = fechaRaw.toDate();

        return {
          'id': doc.id,
          'grupoImagen': data['grupoImagen'] as String? ?? doc.id,
          'nombreFaseDetectada':
              data['nombreFaseDetectada'] as String? ?? 'Sana',
          'faseDetectada': data['faseDetectada'] ?? 0,
          'porcentajeInfeccion':
              (data['porcentajeInfeccion'] as num?)?.toDouble() ?? 0.0,
          'latitud': (data['latitud'] as num?)?.toDouble() ?? 0.0,
          'longitud': (data['longitud'] as num?)?.toDouble() ?? 0.0,
          'imagenURL': data['imagenURL'] as String?,
          'loteNombre': data['loteNombre'] as String?,
          'fechaDeteccion': fecha,
        };
      }).toList();

      // Solo detecciones con coordenadas válidas dentro de Ecuador
      final validas = detecciones
          .where(
            (d) =>
                d['latitud'] != 0.0 &&
                d['longitud'] != 0.0 &&
                Constantes.coordenadasEnEcuador(d['latitud'], d['longitud']),
          )
          .toList();

      debugPrint('🗺️ ${validas.length} detecciones con coordenadas válidas');

      if (!mounted) return;
      setState(() {
        _detecciones = validas;
        _deteccionesFiltradas = validas;
        _cargando = false;
      });

      _aplicarFiltro(_faseSeleccionada);

      // Ajustar cámara si hay puntos
      if (validas.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), _ajustarCamara);
      }
    } catch (e) {
      debugPrint('❌ Error cargando detecciones mapa: $e');
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  void _aplicarFiltro(String? fase) {
    if (!mounted) return;
    setState(() {
      _faseSeleccionada = fase;
      _deteccionesFiltradas = fase == null
          ? _detecciones
          : _detecciones
                .where((d) => d['nombreFaseDetectada'] == fase)
                .toList();
    });
    _crearMarcadores();
  }

  void _crearMarcadores() {
    final markers = <Marker>{};
    for (var det in _deteccionesFiltradas) {
      final lat = det['latitud'] as double;
      final lng = det['longitud'] as double;
      final fase = det['nombreFaseDetectada'] as String;

      markers.add(
        Marker(
          markerId: MarkerId(det['id'] as String),
          position: LatLng(lat, lng),
          icon: _iconoPorFase(fase),
          infoWindow: InfoWindow(
            title: _nombreFaseLegible(fase),
            snippet: 'Toca para ver detalles',
          ),
          onTap: () => _mostrarDetalleDeteccion(det),
        ),
      );
    }
    if (mounted) setState(() => _markers = markers);
    debugPrint('📌 ${_markers.length} marcadores creados');
  }

  // ✅ Maneja tanto formato YOLO ('FASE_INTERMEDIA') como legible ('Fase Intermedia')
  String _nombreFaseLegible(String fase) {
    if (fase.contains('_') || fase == fase.toUpperCase()) {
      return Constantes.obtenerNombreLegible(fase);
    }
    return fase; // Ya viene legible desde Firestore
  }

  BitmapDescriptor _iconoPorFase(String fase) {
    final f = fase.toUpperCase();
    if (f.contains('SANA')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    } else if (f.contains('INICIAL') || f.contains('TEMPRANA')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    } else if (f.contains('INTERMEDIA')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    } else if (f.contains('AVANZADA') || f.contains('MOMIFICADA')) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
    return BitmapDescriptor.defaultMarker;
  }

  Color _colorPorFase(String fase) {
    final f = fase.toUpperCase();
    if (f.contains('SANA')) return const Color(0xFF4CAF50);
    if (f.contains('INICIAL') || f.contains('TEMPRANA'))
      return const Color(0xFFFFC107);
    if (f.contains('INTERMEDIA')) return const Color(0xFFFF9800);
    if (f.contains('AVANZADA') || f.contains('MOMIFICADA'))
      return const Color(0xFFF44336);
    return Colors.grey;
  }

  void _mostrarDetalleDeteccion(Map<String, dynamic> deteccion) {
    if (!mounted) return;
    setState(() => _deteccionSeleccionada = deteccion);
    _slideController.forward();
    _animarCamara(
      CameraUpdate.newLatLngZoom(
        LatLng(deteccion['latitud'] as double, deteccion['longitud'] as double),
        15,
      ),
    );
  }

  void _cerrarDetalle() {
    _slideController.reverse();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _deteccionSeleccionada = null);
    });
  }

  void _toggleListado() {
    if (!mounted) return;
    setState(() => _mostrarListado = !_mostrarListado);
    if (_mostrarListado) {
      _listadoController.forward();
    } else {
      _listadoController.reverse();
    }
  }

  void _ajustarCamara() {
    if (_deteccionesFiltradas.isEmpty || _mapControllerDisposed) return;

    double minLat = _deteccionesFiltradas.first['latitud'];
    double maxLat = minLat;
    double minLng = _deteccionesFiltradas.first['longitud'];
    double maxLng = minLng;

    for (var det in _deteccionesFiltradas) {
      final lat = det['latitud'] as double;
      final lng = det['longitud'] as double;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    // Si todos los puntos son iguales, zoom fijo
    if (minLat == maxLat && minLng == maxLng) {
      _animarCamara(CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 15));
    } else {
      _animarCamara(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // MAPA
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _centroInicial,
              zoom: 12,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              _mapControllerDisposed = false;
              if (_deteccionesFiltradas.isNotEmpty) {
                Future.delayed(
                  const Duration(milliseconds: 300),
                  _ajustarCamara,
                );
              }
            },
            onTap: (_) => _cerrarDetalle(),
          ),

          // HEADER — ✅ FIX 2: sin botón back (está en PageView, no en Navigator)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white.withOpacity(0.95),
                    Colors.white.withOpacity(0),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // ✅ Sin botón back — el mapa vive en PageView
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mapa de detecciones',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Contador de puntos
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: TemaApp.verdePrimario.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_markers.length} punto${_markers.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: TemaApp.verdePrimario,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              _mostrarListado ? Icons.close : Icons.list,
                            ),
                            onPressed: _toggleListado,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.my_location),
                            onPressed: _obtenerUbicacionActual,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _cargarDetecciones,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 2,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // FILTROS
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildChipFiltro(
                              label: 'Todas',
                              fase: null,
                              color: Colors.grey.shade700,
                              total: _detecciones.length,
                            ),
                            const SizedBox(width: 8),
                            ..._fasesDisponibles.map((fase) {
                              final total = _detecciones
                                  .where(
                                    (d) => d['nombreFaseDetectada'] == fase,
                                  )
                                  .length;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _buildChipFiltro(
                                  label: _nombreFaseLegible(fase),
                                  fase: fase,
                                  color: _colorPorFase(fase),
                                  total: total,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // LOADING
          if (_cargando)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: TemaApp.verdePrimario),
                        SizedBox(height: 16),
                        Text('Cargando detecciones...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // LISTADO LATERAL
          if (_mostrarListado)
            Positioned(
              left: 0,
              top: 160,
              bottom: 0,
              child: SlideTransition(
                position: _listadoAnimation,
                child: _buildListadoDetecciones(),
              ),
            ),

          // PANEL DETALLE FLOTANTE
          if (_deteccionSeleccionada != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildPanelDetalle(_deteccionSeleccionada!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro({
    required String label,
    required String? fase,
    required Color color,
    required int total,
  }) {
    final activo = _faseSeleccionada == fase;
    return GestureDetector(
      onTap: () => _aplicarFiltro(fase),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: activo ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: activo ? color : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: activo
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: activo ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$label ($total)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: activo ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListadoDetecciones() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(5, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: TemaApp.verdePrimario,
              borderRadius: BorderRadius.only(topRight: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Lista de detecciones',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _toggleListado,
                ),
              ],
            ),
          ),
          _deteccionesFiltradas.isEmpty
              ? Expanded(
                  child: Center(
                    child: Text(
                      'Sin detecciones\nen esta zona',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              : Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _deteccionesFiltradas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _buildItemListado(_deteccionesFiltradas[i]),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildItemListado(Map<String, dynamic> det) {
    final fase = det['nombreFaseDetectada'] as String;
    final color = _colorPorFase(fase);
    final lote = det['loteNombre'] as String?;

    return GestureDetector(
      onTap: () {
        _mostrarDetalleDeteccion(det);
        _toggleListado();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _nombreFaseLegible(fase),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
            if (lote != null && lote.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 12,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      lote,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPanelDetalle(Map<String, dynamic> det) {
    final fase = det['nombreFaseDetectada'] as String;
    final porcentaje = det['porcentajeInfeccion'] as double;
    final imagenUrl = det['imagenURL'] as String?;
    final lote = det['loteNombre'] as String?;
    final fecha = det['fechaDeteccion'] as DateTime;
    final grupoImagen = det['grupoImagen'] as String?;
    final color = _colorPorFase(fase);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imagenUrl != null && imagenUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: imagenUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 180,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: TemaApp.verdePrimario,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 180,
                      color: Colors.grey.shade100,
                      child: Icon(
                        Icons.image_not_supported,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: _cerrarDetalle,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.close, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _nombreFaseLegible(fase),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${porcentaje.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (lote != null && lote.isNotEmpty) ...[
                  _infoRow(icon: Icons.terrain, label: 'Lote', valor: lote),
                  const SizedBox(height: 8),
                ],
                _infoRow(
                  icon: Icons.calendar_today,
                  label: 'Fecha',
                  valor: _formatearFecha(fecha),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: grupoImagen != null
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetalleDeteccionScreen(
                                grupoImagen: grupoImagen,
                              ),
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Ver detalle completo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TemaApp.verdePrimario,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String valor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  String _formatearFecha(DateTime fecha) {
    const meses = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${fecha.day} ${meses[fecha.month - 1]} ${fecha.year}';
  }
}

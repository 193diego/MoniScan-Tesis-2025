// lib/presentacion/pantallas/historial_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../logica/servicios/servicio_eliminacion.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';
import 'detalle_deteccion_screen.dart';
import 'escaneo_screen.dart';

class HistorialScreen extends StatefulWidget {
  final String cedulaUsuario;
  const HistorialScreen({super.key, required this.cedulaUsuario});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ServicioEliminacion _servicioEliminacion = ServicioEliminacion();

  List<Map<String, dynamic>> _gruposImagenes = [];
  Map<String, Set<String>> _fasesPorGrupo = {};
  bool _cargando = true;
  bool _modoOnline = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _cargarGruposImagenes();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _cargarGruposImagenes() async {
    if (_disposed) return;
    if (mounted) setState(() => _cargando = true);

    try {
      final conectividad = await Connectivity().checkConnectivity();
      final tieneInternet = conectividad != ConnectivityResult.none;

      if (tieneInternet && _modoOnline) {
        try {
          final grupos = await _cargarGruposFirebase();
          if (grupos.isNotEmpty) {
            await _sincronizarConSQLite(grupos);
            if (!_disposed && mounted) {
              setState(() {
                _gruposImagenes = grupos;
                _modoOnline = true;
                _cargando = false;
              });
            }
            return;
          }
        } catch (e) {
          debugPrint('❌ Error Firebase: $e');
        }
      }

      throw Exception('Sin conexión');
    } catch (e) {
      final gruposLocales = await _db.obtenerGruposImagenes(
        widget.cedulaUsuario,
      );

      for (var grupo in gruposLocales) {
        final detecciones = await _db.obtenerDeteccionesPorGrupo(
          grupo['grupoImagen'],
        );
        _fasesPorGrupo[grupo['grupoImagen']] = detecciones
            .map((d) => d.fase)
            .toSet();
      }

      if (!_disposed && mounted) {
        setState(() {
          _gruposImagenes = gruposLocales;
          _modoOnline = false;
          _cargando = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _cargarGruposFirebase() async {
    final snapshot = await _firestore
        .collection('detecciones')
        .where('idUsuario', isEqualTo: widget.cedulaUsuario)
        .orderBy('timestamp', descending: true)
        .get();

    if (snapshot.docs.isEmpty) return [];

    final Map<String, Map<String, dynamic>> gruposMap = {};
    final Map<String, Set<String>> fasesPorGrupoTemp = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final grupoImagen = data['grupoImagen'] as String?;
      final fase = data['fase'] as String;

      if (grupoImagen == null || grupoImagen.isEmpty) continue;

      if (!gruposMap.containsKey(grupoImagen)) {
        gruposMap[grupoImagen] = {
          'grupoImagen': grupoImagen,
          'imagenUrl': data['imagenUrl'],
          'timestamp': data['timestamp'] ?? data['fecha'],
          'totalDetecciones': 1,
          'lote': data['lote'],
        };
        fasesPorGrupoTemp[grupoImagen] = {fase};
      } else {
        gruposMap[grupoImagen]!['totalDetecciones'] =
            (gruposMap[grupoImagen]!['totalDetecciones'] as int) + 1;
        fasesPorGrupoTemp[grupoImagen]!.add(fase);
      }
    }

    _fasesPorGrupo = fasesPorGrupoTemp;
    return gruposMap.values.toList();
  }

  Future<void> _sincronizarConSQLite(
    List<Map<String, dynamic>> gruposFirebase,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('detecciones')
          .where('idUsuario', isEqualTo: widget.cedulaUsuario)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final deteccion = Deteccion(
          idMazorca: data['idMazorca'],
          grupoImagen: data['grupoImagen'],
          idUsuario: data['idUsuario'],
          workerId: data['workerId'],
          fase: data['fase'],
          confianza: (data['confianza'] as num).toDouble(),
          severidad: data['severidad'],
          colorSemaforo: data['colorSemaforo'],
          rutaImagen: data['imagenUrl'],
          latitud: (data['latitud'] as num?)?.toDouble() ?? 0.0,
          longitud: (data['longitud'] as num?)?.toDouble() ?? 0.0,
          direccion: data['direccion'],
          lote: data['lote'],
          notas: data['notas'],
          fecha: (data['timestamp'] ?? data['fecha']).toDate(),
          sincronizado: true,
        );
        await _db.insertarDeteccion(deteccion);
      }
    } catch (e) {
      debugPrint('❌ Error sincronizando: $e');
    }
  }

  Future<void> _eliminarGrupo(String grupoImagen) async {
    if (_disposed) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar'),
        content: const Text('¿Eliminar esta imagen y todas sus detecciones?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || _disposed) return;
    if (!mounted || _disposed) return;

    _mostrarDialogoCarga('Eliminando...');
    try {
      final exito = await _servicioEliminacion.eliminarGrupoImagen(
        grupoImagen: grupoImagen,
        idUsuario: widget.cedulaUsuario,
      );
      if (!_disposed && mounted) {
        Navigator.pop(context);
        if (exito) {
          await _cargarGruposImagenes();
          if (!_disposed && mounted) _mostrarMensaje('✅ Eliminado');
        } else {
          _mostrarError('Error eliminando');
        }
      }
    } catch (e) {
      if (!_disposed && mounted) {
        Navigator.pop(context);
        _mostrarError('Error: $e');
      }
    }
  }

  Future<void> _verDetalle(String? grupoImagen) async {
    if (_disposed || grupoImagen == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalleDeteccionScreen(grupoImagen: grupoImagen),
      ),
    ).then((_) {
      if (!_disposed && mounted) _cargarGruposImagenes();
    });
  }

  Future<void> _darSeguimiento(String? grupoImagen) async {
    if (_disposed || grupoImagen == null) return;
    try {
      List<Deteccion> detecciones = await _db.obtenerDeteccionesPorGrupo(
        grupoImagen,
      );
      if (detecciones.isEmpty) {
        final snapshot = await _firestore
            .collection('detecciones')
            .where('grupoImagen', isEqualTo: grupoImagen)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          final data = snapshot.docs.first.data();
          detecciones = [
            Deteccion(
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
            ),
          ];
        }
      }
      if (detecciones.isEmpty) {
        if (!_disposed && mounted)
          _mostrarError('No se encontraron detecciones');
        return;
      }
      if (!_disposed && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EscaneoScreen(
              cedulaUsuario: widget.cedulaUsuario,
              idMazorcaSeguimiento: detecciones.first.idMazorca,
              grupoImagenSeguimiento: grupoImagen,
            ),
          ),
        ).then((_) {
          if (!_disposed && mounted) _cargarGruposImagenes();
        });
      }
    } catch (e) {
      if (!_disposed && mounted) _mostrarError('Error: $e');
    }
  }

  void _mostrarDialogoCarga(String mensaje) {
    if (!mounted || _disposed) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IndicadorCarga(mensaje: mensaje),
          ),
        ),
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _mostrarError(String mensaje) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: TemaApp.verdePrimario,
        actions: [
          IconButton(
            icon: Icon(_modoOnline ? Icons.cloud : Icons.cloud_off),
            onPressed: () {
              setState(() => _modoOnline = !_modoOnline);
              _cargarGruposImagenes();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarGruposImagenes,
          ),
        ],
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando...')
          : _gruposImagenes.isEmpty
          ? const Center(child: Text('No hay detecciones'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: _modoOnline
                      ? Colors.blue.shade50
                      : Colors.orange.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _modoOnline ? Icons.cloud : Icons.cloud_off,
                        size: 16,
                        color: _modoOnline ? Colors.blue : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _modoOnline ? 'Modo Online' : 'Modo Offline',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _modoOnline ? Colors.blue : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _cargarGruposImagenes,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _gruposImagenes.length,
                      itemBuilder: (context, index) {
                        final grupo = _gruposImagenes[index];
                        final fases =
                            _fasesPorGrupo[grupo['grupoImagen']]?.toList() ??
                            [];
                        return _TarjetaGrupoImagen(
                          grupo: grupo,
                          fases: fases,
                          modoOnline: _modoOnline,
                          onTap: () => _verDetalle(grupo['grupoImagen']),
                          onEliminar: () =>
                              _eliminarGrupo(grupo['grupoImagen']),
                          onSeguimiento: () =>
                              _darSeguimiento(grupo['grupoImagen']),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _TarjetaGrupoImagen extends StatelessWidget {
  final Map<String, dynamic> grupo;
  final List<String> fases;
  final bool modoOnline;
  final VoidCallback onTap;
  final VoidCallback onEliminar;
  final VoidCallback onSeguimiento;

  const _TarjetaGrupoImagen({
    required this.grupo,
    required this.fases,
    required this.modoOnline,
    required this.onTap,
    required this.onEliminar,
    required this.onSeguimiento,
  });

  @override
  Widget build(BuildContext context) {
    final imagenUrl = grupo['imagenUrl'] as String?;
    final totalDetecciones = grupo['totalDetecciones'] as int;
    final grupoId = (grupo['grupoImagen'] as String).substring(0, 8);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (imagenUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: modoOnline && imagenUrl.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: imagenUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (c, u, e) => Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 50),
                      ),
                    )
                  : Image.file(
                      File(imagenUrl),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 50),
                      ),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Imagen $grupoId',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      onPressed: onTap,
                      color: TemaApp.verdePrimario,
                    ),
                    IconButton(
                      icon: const Icon(Icons.timeline),
                      onPressed: onSeguimiento,
                      color: Colors.blue,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onEliminar,
                      color: Colors.red,
                    ),
                  ],
                ),
                if (fases.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: fases
                        .map((f) => EtiquetaFase(fase: f, tamanoTexto: 11))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Text('$totalDetecciones detecciones'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

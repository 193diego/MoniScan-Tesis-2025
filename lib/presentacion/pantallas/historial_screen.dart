// lib/presentacion/pantallas/historial_screen.dart
// ✅ CORRECCIÓN: _darSeguimiento ahora muestra diálogo con 2 opciones
//    (Cámara en tiempo real / Subir imagen) en vez de ir directo al escaneo.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';
import 'detalle_deteccion_screen.dart';
import 'escaneo_screen.dart';
import 'subir_imagen_screen.dart';

class HistorialScreen extends StatefulWidget {
  final String cedulaUsuario;
  const HistorialScreen({super.key, required this.cedulaUsuario});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final BaseDatosHelper _db = BaseDatosHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _gruposImagenes = [];
  Map<String, Set<String>> _fasesPorGrupo = {};
  bool _cargando = true;
  bool _modoOnline = false;
  bool _disposed = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    if (_disposed) return;
    if (mounted) setState(() => _cargando = true);

    try {
      final conectividad = await Connectivity().checkConnectivity();
      final tieneInternet = conectividad != ConnectivityResult.none;
      if (tieneInternet) {
        await _cargarDesdeFirebase();
      } else {
        await _cargarDesdeLocal();
      }
    } catch (e) {
      debugPrint('❌ Error general: $e');
      await _cargarDesdeLocal();
    }
  }

  Future<void> _cargarDesdeFirebase() async {
    try {
      debugPrint('☁️ Cargando historial Firebase — UID: $_uid');

      final snapshot = await _firestore
          .collection('detecciones')
          .where('trabajadorUID', isEqualTo: _uid)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ Sin detecciones en Firebase, cargando local...');
        await _cargarDesdeLocal();
        return;
      }

      final Map<String, Map<String, dynamic>> gruposMap = {};
      final Map<String, Set<String>> fasesPorGrupoTemp = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final grupoId = (data['grupoImagen'] as String?)?.isNotEmpty == true
            ? data['grupoImagen'] as String
            : doc.id;

        final fase = data['nombreFaseDetectada'] as String? ?? 'Sana';

        String fechaStr = '';
        final fechaRaw = data['fechaDeteccion'] ?? data['creadoEn'];
        if (fechaRaw is Timestamp) {
          fechaStr = fechaRaw.toDate().toIso8601String();
        }

        if (!gruposMap.containsKey(grupoId)) {
          gruposMap[grupoId] = {
            'grupoImagen': grupoId,
            'primerDocId': doc.id,
            'imagenUrl': data['imagenURL'] as String?,
            'timestamp': fechaStr,
            'totalDetecciones': 1,
            'lote': data['loteNombre'] as String?,
            'latitud': (data['latitud'] as num?)?.toDouble(),
            'longitud': (data['longitud'] as num?)?.toDouble(),
          };
          fasesPorGrupoTemp[grupoId] = {fase};
        } else {
          gruposMap[grupoId]!['totalDetecciones'] =
              (gruposMap[grupoId]!['totalDetecciones'] as int) + 1;
          fasesPorGrupoTemp[grupoId]!.add(fase);
        }
      }

      final grupos = gruposMap.values.toList()
        ..sort((a, b) {
          final fa = a['timestamp'] as String? ?? '';
          final fb = b['timestamp'] as String? ?? '';
          return fb.compareTo(fa);
        });

      if (!_disposed && mounted) {
        setState(() {
          _gruposImagenes = grupos;
          _fasesPorGrupo = fasesPorGrupoTemp;
          _modoOnline = true;
          _cargando = false;
        });
      }
      debugPrint('✅ ${grupos.length} grupos cargados desde Firebase');
    } catch (e) {
      debugPrint('❌ Error Firebase: $e');
      await _cargarDesdeLocal();
    }
  }

  Future<void> _cargarDesdeLocal() async {
    debugPrint('💾 Cargando historial local — cédula: ${widget.cedulaUsuario}');
    try {
      final grupos = await _db.obtenerGruposImagenes(widget.cedulaUsuario);

      for (var grupo in grupos) {
        final detecciones = await _db.obtenerDeteccionesPorGrupo(
          grupo['grupoImagen'],
        );
        _fasesPorGrupo[grupo['grupoImagen']] = detecciones
            .map((d) => d.fase)
            .toSet();
      }

      if (!_disposed && mounted) {
        setState(() {
          _gruposImagenes = grupos;
          _modoOnline = false;
          _cargando = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error local: $e');
      if (!_disposed && mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _eliminarGrupo(String grupoImagen) async {
    if (_disposed) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('Confirmar eliminación', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          '¿Eliminar esta imagen y todas sus detecciones?\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || _disposed || !mounted) return;

    try {
      final snap = await _firestore
          .collection('detecciones')
          .where('grupoImagen', isEqualTo: grupoImagen)
          .where('trabajadorUID', isEqualTo: _uid)
          .get();

      for (var doc in snap.docs) {
        await doc.reference.delete();
        debugPrint('🗑️ Documento ${doc.id} eliminado de Firebase');
      }

      await _db.eliminarDeteccionesPorGrupo(grupoImagen);

      await _cargarHistorial();
      if (!_disposed && mounted) _mostrarMensaje('✅ Eliminado correctamente');
    } catch (e) {
      if (!_disposed && mounted) _mostrarError('Error al eliminar: $e');
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
      if (!_disposed && mounted) _cargarHistorial();
    });
  }

  // ✅ CORRECCIÓN: Muestra diálogo con 2 opciones antes de iniciar seguimiento.
  // El usuario elige entre "Cámara en tiempo real" o "Subir imagen".
  Future<void> _darSeguimiento(String grupoImagen) async {
    if (_disposed) return;

    // 1) Obtener idMazorca desde SQLite
    String idMazorca;
    try {
      final detecciones = await _db.obtenerDeteccionesPorGrupo(grupoImagen);
      idMazorca = detecciones.isNotEmpty
          ? detecciones.first.idMazorca
          : grupoImagen;
    } catch (_) {
      idMazorca = grupoImagen;
    }

    if (_disposed || !mounted) return;

    // 2) Mostrar diálogo de selección de método
    final opcion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.timeline, color: TemaApp.verdePrimario, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Dar seguimiento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Cómo deseas analizar la mazorca para el seguimiento?',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Opción cámara en tiempo real
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'camara'),
                icon: const Icon(Icons.videocam, size: 20),
                label: const Text('Cámara en tiempo real'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemaApp.verdePrimario,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Opción subir imagen
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'galeria'),
                icon: const Icon(Icons.image, size: 20),
                label: const Text('Subir imagen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaApp.verdePrimario,
                  side: const BorderSide(color: TemaApp.verdePrimario),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (opcion == null || _disposed || !mounted) return;

    // 3) Navegar según la opción elegida
    if (opcion == 'camara') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EscaneoScreen(
            usuarioId: widget.cedulaUsuario,
            onVolverInicio: () => Navigator.pop(context),
            grupoImagenSeguimiento: grupoImagen,
            idMazorcaSeguimiento: idMazorca,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SubirImagenScreen(
            cedulaUsuario: widget.cedulaUsuario,
            grupoImagenSeguimiento: grupoImagen,
            idMazorcaSeguimiento: idMazorca,
          ),
        ),
      );
    }

    if (!_disposed && mounted) _cargarHistorial();
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _mostrarError(String mensaje) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Historial',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: TemaApp.verdePrimario,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _modoOnline ? Icons.cloud_done : Icons.cloud_off,
              color: Colors.white,
            ),
            tooltip: _modoOnline ? 'Online' : 'Offline',
            onPressed: _cargarHistorial,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarHistorial,
          ),
        ],
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando historial...')
          : _gruposImagenes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 24),
                  Text(
                    'No hay detecciones guardadas',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Usa el escáner para crear tu primera detección',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarHistorial,
              color: TemaApp.verdePrimario,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _gruposImagenes.length,
                itemBuilder: (context, index) {
                  final grupo = _gruposImagenes[index];
                  final grupoId = grupo['grupoImagen'] as String;
                  return _TarjetaGrupoImagen(
                    grupo: grupo,
                    fases: _fasesPorGrupo[grupoId] ?? {},
                    modoOnline: _modoOnline,
                    onEliminar: () => _eliminarGrupo(grupoId),
                    onVerDetalle: () => _verDetalle(grupoId),
                    onDarSeguimiento: () => _darSeguimiento(grupoId),
                  );
                },
              ),
            ),
    );
  }
}

// ── Tarjeta ───────────────────────────────────────────────────────────────────

class _TarjetaGrupoImagen extends StatelessWidget {
  final Map<String, dynamic> grupo;
  final Set<String> fases;
  final bool modoOnline;
  final VoidCallback onEliminar;
  final VoidCallback onVerDetalle;
  final VoidCallback onDarSeguimiento;

  const _TarjetaGrupoImagen({
    required this.grupo,
    required this.fases,
    required this.modoOnline,
    required this.onEliminar,
    required this.onVerDetalle,
    required this.onDarSeguimiento,
  });

  @override
  Widget build(BuildContext context) {
    final grupoImagen = grupo['grupoImagen'] as String;
    final imagenUrl = grupo['imagenUrl'] as String?;
    final totalDetecciones = grupo['totalDetecciones'] as int? ?? 1;
    final lote = grupo['lote'] as String?;
    final esUrlFirebase = imagenUrl != null && imagenUrl.startsWith('http');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen
          if (imagenUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: esUrlFirebase
                  ? CachedNetworkImage(
                      imageUrl: imagenUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 200,
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: TemaApp.verdePrimario,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 200,
                        color: Colors.grey.shade100,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Error al cargar imagen',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      height: 200,
                      color: Colors.grey.shade100,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pendiente de sincronización',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header con ID y contador
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: TemaApp.verdeClaro.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: TemaApp.verdeSecundario.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        'ID: ${grupoImagen.length > 8 ? grupoImagen.substring(0, 8) : grupoImagen}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: TemaApp.verdePrimario,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$totalDetecciones detección${totalDetecciones > 1 ? 'es' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),

                if (lote != null && lote.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lote,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (fases.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: fases.map((fase) {
                      final color = _getColorFase(fase);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Text(
                          fase,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 16),

                // Botones
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onVerDetalle,
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('Ver detalle'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TemaApp.verdePrimario,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDarSeguimiento,
                        icon: const Icon(Icons.trending_up, size: 18),
                        label: const Text('Seguimiento'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TemaApp.verdePrimario,
                          side: const BorderSide(color: TemaApp.verdePrimario),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onEliminar,
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red.shade400,
                      tooltip: 'Eliminar',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorFase(String fase) {
    final f = fase.toUpperCase();
    if (f.contains('SANA')) return Colors.green;
    if (f.contains('INICIAL')) return Colors.yellow.shade700;
    if (f.contains('INTERMEDIA')) return Colors.orange;
    if (f.contains('AVANZADA')) return Colors.red;
    return Colors.grey;
  }
}

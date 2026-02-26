// lib/presentacion/pantallas/detalle_deteccion_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';

class DetalleDeteccionScreen extends StatefulWidget {
  final String grupoImagen;
  const DetalleDeteccionScreen({super.key, required this.grupoImagen});

  @override
  State<DetalleDeteccionScreen> createState() => _DetalleDeteccionScreenState();
}

class _DetalleDeteccionScreenState extends State<DetalleDeteccionScreen> {
  final BaseDatosHelper _bd = BaseDatosHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<_DeteccionUI> _detecciones = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDetecciones();
  }

  Future<void> _cargarDetecciones() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    // 1️⃣ Intentar desde Firestore
    try {
      final snapshot = await _firestore
          .collection('detecciones')
          .where('grupoImagen', isEqualTo: widget.grupoImagen)
          .where('trabajadorUID', isEqualTo: _uid)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final lista = snapshot.docs.map((doc) {
          final data = doc.data();
          DateTime fecha = DateTime.now();
          final fechaRaw = data['fechaDeteccion'] ?? data['creadoEn'];
          if (fechaRaw is Timestamp) fecha = fechaRaw.toDate();

          return _DeteccionUI(
            fase: data['nombreFaseDetectada'] as String? ?? 'Sana',
            confianza: ((data['porcentajeInfeccion'] as num?) ?? 0) / 100,
            imagenUrl: data['imagenURL'] as String? ?? '',
            fecha: fecha,
            lote: data['loteNombre'] as String?,
            observaciones: data['observaciones'] as String?,
            latitud: (data['latitud'] as num?)?.toDouble() ?? 0,
            longitud: (data['longitud'] as num?)?.toDouble() ?? 0,
            sincronizado: true,
          );
        }).toList();

        if (!mounted) return;
        setState(() {
          _detecciones = lista;
          _cargando = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Error Firebase, usando SQLite: $e');
    }

    // 2️⃣ Fallback: SQLite local
    try {
      final detecciones = await _bd.obtenerDeteccionesPorGrupo(
        widget.grupoImagen,
      );
      if (!mounted) return;

      if (detecciones.isEmpty) {
        setState(() {
          _error =
              'No se encontraron detecciones para este grupo.\n\nEs posible que los datos aún no estén sincronizados.';
          _cargando = false;
        });
        return;
      }

      setState(() {
        _detecciones = detecciones
            .map(
              (d) => _DeteccionUI(
                fase: d.fase,
                confianza: d.confianza,
                imagenUrl: d.rutaImagen,
                fecha: d.fecha,
                lote: d.lote,
                observaciones: d.notas,
                latitud: d.latitud,
                longitud: d.longitud,
                sincronizado: d.sincronizado,
              ),
            )
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar detecciones: $e';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final idCorto = widget.grupoImagen.length > 8
        ? widget.grupoImagen.substring(0, 8)
        : widget.grupoImagen;

    return Scaffold(
      backgroundColor: TemaApp.colorFondo,
      appBar: AppBar(
        title: Text(
          'Detalle — $idCorto',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: TemaApp.verdePrimario,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarDetecciones,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: TemaApp.verdePrimario),
                  SizedBox(height: 16),
                  Text('Cargando detecciones...'),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _cargarDetecciones,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TemaApp.verdePrimario,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _detecciones.length,
              itemBuilder: (context, index) =>
                  _TarjetaDeteccion(deteccion: _detecciones[index]),
            ),
    );
  }
}

// ── Modelo UI ─────────────────────────────────────────────────────────────────

class _DeteccionUI {
  final String fase;
  final double confianza;
  final String imagenUrl;
  final DateTime fecha;
  final String? lote;
  final String? observaciones;
  final double latitud;
  final double longitud;
  final bool sincronizado;

  const _DeteccionUI({
    required this.fase,
    required this.confianza,
    required this.imagenUrl,
    required this.fecha,
    this.lote,
    this.observaciones,
    required this.latitud,
    required this.longitud,
    required this.sincronizado,
  });
}

// ── Tarjeta de detección ──────────────────────────────────────────────────────

class _TarjetaDeteccion extends StatefulWidget {
  final _DeteccionUI deteccion;
  const _TarjetaDeteccion({required this.deteccion});

  @override
  State<_TarjetaDeteccion> createState() => _TarjetaDeteccionState();
}

class _TarjetaDeteccionState extends State<_TarjetaDeteccion> {
  // Estado del panel de tratamiento
  bool _tratamientoExpandido = false;
  bool _cargandoTratamiento = false;
  Map<String, dynamic>? _tratamiento;
  bool _tratamientoBuscado = false; // evita re-consultar cada vez

  /// Convierte la fase (legible o YOLO) al formato YOLO para buscar en Firestore
  String _faseAFormatoYolo(String fase) {
    // Si ya es formato YOLO, devolverlo tal cual
    if (Constantes.nombresClases.contains(fase)) return fase;
    // Mapear formato legible → YOLO
    const mapa = {
      'Sana': 'SANA',
      'Fase Inicial': 'FASE_INICIAL',
      'Fase Intermedia': 'FASE_INTERMEDIA',
      'Fase Avanzada': 'FASE_AVANZADA',
    };
    return mapa[fase] ?? 'SANA';
  }

  Future<void> _cargarTratamiento() async {
    if (_tratamientoBuscado) return; // ya consultamos, no repetir
    setState(() => _cargandoTratamiento = true);

    try {
      final faseYolo = _faseAFormatoYolo(widget.deteccion.fase);
      final query = await FirebaseFirestore.instance
          .collection('tratamientos')
          .where('fase', isEqualTo: faseYolo)
          .limit(1)
          .get();

      if (mounted) {
        setState(() {
          _tratamiento = query.docs.isNotEmpty ? query.docs.first.data() : null;
          _cargandoTratamiento = false;
          _tratamientoBuscado = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando tratamiento en detalle: $e');
      if (mounted) {
        setState(() {
          _cargandoTratamiento = false;
          _tratamientoBuscado = true;
        });
      }
    }
  }

  void _toggleTratamiento() {
    setState(() => _tratamientoExpandido = !_tratamientoExpandido);
    // Consultar Firebase la primera vez que se expande
    if (_tratamientoExpandido && !_tratamientoBuscado) {
      _cargarTratamiento();
    }
  }

  // ── Helpers de color ────────────────────────────────────────────────────────

  bool _esFaseYolo(String fase) =>
      fase == fase.toUpperCase() && !fase.contains(' ');

  Color _colorFase(String fase) {
    if (_esFaseYolo(fase)) return Constantes.obtenerColorPorClase(fase);
    final f = fase.toLowerCase();
    if (f.contains('sana')) return const Color(0xFF4CAF50);
    if (f.contains('inicial')) return const Color(0xFFFFC107);
    if (f.contains('intermedia')) return const Color(0xFFFF9800);
    if (f.contains('avanzada')) return const Color(0xFFF44336);
    return const Color(0xFF4CAF50);
  }

  Color _urgenciaColor(String u) {
    switch (u.toLowerCase()) {
      case 'crítica':
      case 'critica':
        return Colors.red;
      case 'alta':
        return Colors.orange;
      case 'media':
        return Colors.amber.shade700;
      default:
        return Colors.green;
    }
  }

  String _nombreFase(String fase) =>
      _esFaseYolo(fase) ? Constantes.obtenerNombreLegible(fase) : fase;

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorFase = _colorFase(widget.deteccion.fase);
    final nombreFase = _nombreFase(widget.deteccion.fase);
    final esUrlFirebase = widget.deteccion.imagenUrl.startsWith('http');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Imagen ──────────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: esUrlFirebase
                ? CachedNetworkImage(
                    imageUrl: widget.deteccion.imagenUrl,
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => Container(
                      height: 250,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: TemaApp.verdePrimario,
                        ),
                      ),
                    ),
                    errorWidget: (ctx, url, err) => _imagenError(),
                  )
                : widget.deteccion.imagenUrl.isNotEmpty
                ? Image.file(
                    File(widget.deteccion.imagenUrl),
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, st) => _imagenError(),
                  )
                : _imagenError(),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Fase y confianza ─────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colorFase,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        nombreFase,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorFase.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorFase.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${(widget.deteccion.confianza * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorFase,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // ── Info rows ────────────────────────────────────────────────
                _infoRow(
                  icon: Icons.calendar_today,
                  titulo: 'Fecha',
                  valor: _formatearFecha(widget.deteccion.fecha),
                ),
                const SizedBox(height: 12),
                _infoRow(
                  icon: Icons.location_on,
                  titulo: 'Coordenadas',
                  valor:
                      '${widget.deteccion.latitud.toStringAsFixed(6)}, ${widget.deteccion.longitud.toStringAsFixed(6)}',
                ),
                if (widget.deteccion.lote != null &&
                    widget.deteccion.lote!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _infoRow(
                    icon: Icons.terrain,
                    titulo: 'Lote',
                    valor: widget.deteccion.lote!,
                  ),
                ],
                if (widget.deteccion.observaciones != null &&
                    widget.deteccion.observaciones!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _infoRow(
                    icon: Icons.note,
                    titulo: 'Observaciones',
                    valor: widget.deteccion.observaciones!,
                  ),
                ],

                const SizedBox(height: 16),

                // ── Estado sincronización ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.deteccion.sincronizado
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.deteccion.sincronizado
                          ? Colors.green.shade200
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.deteccion.sincronizado
                            ? Icons.cloud_done
                            : Icons.cloud_upload,
                        color: widget.deteccion.sincronizado
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.deteccion.sincronizado
                            ? 'Sincronizado con Firebase'
                            : 'Pendiente de sincronización',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.deteccion.sincronizado
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Tarjeta expandible de tratamiento ────────────────────────
                _TarjetaTratamientoExpandible(
                  expandido: _tratamientoExpandido,
                  cargando: _cargandoTratamiento,
                  tratamiento: _tratamiento,
                  buscado: _tratamientoBuscado,
                  onTap: _toggleTratamiento,
                  urgenciaColor: _urgenciaColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagenError() => Container(
    height: 250,
    color: Colors.grey.shade100,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 8),
        Text(
          'Imagen no disponible',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _infoRow({
    required IconData icon,
    required String titulo,
    required String valor,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: Colors.grey.shade600),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              valor,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    ],
  );

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
    return '${fecha.day} ${meses[fecha.month - 1]} ${fecha.year}, '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }
}

// ── Tarjeta expandible de tratamiento ─────────────────────────────────────────

class _TarjetaTratamientoExpandible extends StatelessWidget {
  final bool expandido;
  final bool cargando;
  final bool buscado;
  final Map<String, dynamic>? tratamiento;
  final VoidCallback onTap;
  final Color Function(String) urgenciaColor;

  const _TarjetaTratamientoExpandible({
    required this.expandido,
    required this.cargando,
    required this.buscado,
    required this.tratamiento,
    required this.onTap,
    required this.urgenciaColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: expandido ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expandido
              ? TemaApp.verdePrimario.withOpacity(0.4)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          // ── Cabecera (siempre visible, tap para expandir) ─────────────────
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.medical_services_outlined,
                    color: expandido
                        ? TemaApp.verdePrimario
                        : Colors.grey.shade600,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '¿Qué hacer con esta planta?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: expandido
                            ? TemaApp.verdePrimario
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  // Indicador de carga o flecha
                  if (cargando)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TemaApp.verdePrimario,
                      ),
                    )
                  else
                    Icon(
                      expandido
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: expandido
                          ? TemaApp.verdePrimario
                          : Colors.grey.shade500,
                    ),
                ],
              ),
            ),
          ),

          // ── Contenido expandible ──────────────────────────────────────────
          if (expandido) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: cargando
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(
                          color: TemaApp.verdePrimario,
                        ),
                      ),
                    )
                  : buscado && tratamiento == null
                  // Sin protocolo configurado
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No hay protocolo configurado para esta fase. '
                            'La administradora debe crearlo desde el panel web.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    )
                  // Protocolo encontrado
                  : _ContenidoProtocolo(
                      tratamiento: tratamiento!,
                      urgenciaColor: urgenciaColor,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Contenido del protocolo ───────────────────────────────────────────────────

class _ContenidoProtocolo extends StatelessWidget {
  final Map<String, dynamic> tratamiento;
  final Color Function(String) urgenciaColor;

  const _ContenidoProtocolo({
    required this.tratamiento,
    required this.urgenciaColor,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = tratamiento['nombre'] as String? ?? '';
    final descripcion = tratamiento['descripcion'] as String? ?? '';
    final urgencia = tratamiento['urgencia'] as String? ?? 'baja';
    final acciones = (tratamiento['acciones'] as List?)?.cast<String>() ?? [];
    final fungicidas =
        (tratamiento['fungicidas'] as List?)?.cast<String>() ?? [];
    final colorUrgencia = urgenciaColor(urgencia);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nombre del protocolo
        if (nombre.isNotEmpty) ...[
          Text(
            nombre,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Nivel de urgencia
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorUrgencia.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorUrgencia.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: colorUrgencia, size: 16),
              const SizedBox(width: 6),
              Text(
                'Urgencia: ${urgencia.toUpperCase()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorUrgencia,
                ),
              ),
            ],
          ),
        ),

        // Descripción
        if (descripcion.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            descripcion,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        // Acciones de campo
        if (acciones.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'ACCIONES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          ...acciones.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✓ ',
                    style: TextStyle(
                      color: TemaApp.verdePrimario,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Expanded(
                    child: Text(a, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Fungicidas / productos
        if (fungicidas.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'SUGERENCIAS QUÍMICAS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: fungicidas
                .map(
                  (f) => Chip(
                    label: Text(f, style: const TextStyle(fontSize: 11)),
                    backgroundColor: TemaApp.verdeClaro,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

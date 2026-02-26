// lib/presentacion/pantallas/seguimiento_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';
import 'escaneo_screen.dart';
import 'subir_imagen_screen.dart';

class SeguimientoScreen extends StatefulWidget {
  final String cedulaUsuario;
  const SeguimientoScreen({super.key, required this.cedulaUsuario});

  @override
  State<SeguimientoScreen> createState() => _SeguimientoScreenState();
}

class _SeguimientoScreenState extends State<SeguimientoScreen> {
  final BaseDatosHelper _db = BaseDatosHelper();
  Map<String, List<Deteccion>> _seguimientosPorMazorca = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarSeguimientos();
  }

  Future<void> _cargarSeguimientos() async {
    setState(() => _cargando = true);
    try {
      final todasDetecciones = await _db.obtenerTodasDetecciones(
        widget.cedulaUsuario,
      );

      final Map<String, List<Deteccion>> seguimientos = {};
      for (var d in todasDetecciones) {
        seguimientos.putIfAbsent(d.idMazorca, () => []).add(d);
      }

      // Ordenar cada mazorca cronológicamente (más antigua primero = línea de tiempo)
      seguimientos.forEach((_, lista) {
        lista.sort((a, b) => a.fecha.compareTo(b.fecha));
      });

      // Solo mostrar mazorcas con más de un registro (tienen seguimiento real)
      final filtrado = Map.fromEntries(
        seguimientos.entries.where((e) => e.value.length > 1),
      );

      // Ordenar por fecha del último registro (más reciente primero)
      final ordenado = Map.fromEntries(
        filtrado.entries.toList()
          ..sort((a, b) => b.value.last.fecha.compareTo(a.value.last.fecha)),
      );

      setState(() {
        _seguimientosPorMazorca = ordenado;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      debugPrint('Error cargando seguimientos: $e');
    }
  }

  void _agregarSeguimiento(String idMazorca, String grupoImagen) async {
    final opcion = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_circle, color: TemaApp.verdePrimario, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nueva evaluación',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text('¿Cómo deseas analizar la mazorca?'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, 'camara'),
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'galeria'),
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
                onPressed: () => Navigator.pop(context, null),
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

    if (opcion == null || !mounted) return;

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

    if (mounted) _cargarSeguimientos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaApp.colorFondo,
      appBar: AppBar(
        title: const Text(
          'Seguimiento de Mazorcas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: TemaApp.verdePrimario,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarSeguimientos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: TemaApp.verdePrimario),
            )
          : _seguimientosPorMazorca.isEmpty
          ? _buildEstadoVacio()
          : RefreshIndicator(
              onRefresh: _cargarSeguimientos,
              color: TemaApp.verdePrimario,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                itemCount: _seguimientosPorMazorca.length,
                itemBuilder: (context, index) {
                  final idMazorca = _seguimientosPorMazorca.keys.elementAt(
                    index,
                  );
                  final detecciones = _seguimientosPorMazorca[idMazorca]!;
                  return _TarjetaSeguimiento(
                    idMazorca: idMazorca,
                    detecciones: detecciones,
                    onAgregar: () => _agregarSeguimiento(
                      idMazorca,
                      detecciones.first.grupoImagen ?? idMazorca,
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: TemaApp.verdeClaro.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timeline,
                size: 64,
                color: TemaApp.verdePrimario,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Sin seguimientos activos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Para ver el seguimiento de una mazorca, entra al Historial, selecciona una detección y presiona "Seguimiento".',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de seguimiento con línea de tiempo ────────────────────────────────

class _TarjetaSeguimiento extends StatefulWidget {
  final String idMazorca;
  final List<Deteccion> detecciones; // ordenadas cronológicamente
  final VoidCallback onAgregar;

  const _TarjetaSeguimiento({
    required this.idMazorca,
    required this.detecciones,
    required this.onAgregar,
  });

  @override
  State<_TarjetaSeguimiento> createState() => _TarjetaSeguimientoState();
}

class _TarjetaSeguimientoState extends State<_TarjetaSeguimiento> {
  bool _expandida = false;

  // ── Helpers de color e icono ─────────────────────────────────────────────

  Color _colorFase(String fase) {
    final f = fase.toLowerCase();
    if (f.contains('sana')) return const Color(0xFF2E7D32);
    if (f.contains('inicial')) return const Color(0xFFF9A825);
    if (f.contains('intermedia')) return const Color(0xFFE65100);
    if (f.contains('avanzada')) return const Color(0xFFC62828);
    return Colors.grey.shade500;
  }

  IconData _iconoFase(String fase) {
    final f = fase.toLowerCase();
    if (f.contains('sana')) return Icons.check_circle_rounded;
    if (f.contains('inicial')) return Icons.warning_amber_rounded;
    if (f.contains('intermedia')) return Icons.error_rounded;
    if (f.contains('avanzada')) return Icons.dangerous_rounded;
    return Icons.help_rounded;
  }

  String _nombreFase(String fase) {
    if (Constantes.nombresClases.contains(fase)) {
      return Constantes.obtenerNombreLegible(fase);
    }
    return fase;
  }

  // Calcula si la enfermedad está progresando, estable o mejorando
  String _tendencia() {
    if (widget.detecciones.length < 2) return 'estable';
    final primera = _severidadFase(widget.detecciones.first.fase);
    final ultima = _severidadFase(widget.detecciones.last.fase);
    if (ultima > primera) return 'empeorando';
    if (ultima < primera) return 'mejorando';
    return 'estable';
  }

  int _severidadFase(String fase) {
    final f = fase.toLowerCase();
    if (f.contains('sana')) return 0;
    if (f.contains('inicial')) return 1;
    if (f.contains('intermedia')) return 2;
    if (f.contains('avanzada')) return 3;
    return 0;
  }

  Color _colorTendencia() {
    switch (_tendencia()) {
      case 'empeorando':
        return Colors.red.shade600;
      case 'mejorando':
        return Colors.green.shade600;
      default:
        return Colors.blue.shade600;
    }
  }

  IconData _iconoTendencia() {
    switch (_tendencia()) {
      case 'empeorando':
        return Icons.trending_up;
      case 'mejorando':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  String _textoTendencia() {
    switch (_tendencia()) {
      case 'empeorando':
        return 'Progresando';
      case 'mejorando':
        return 'Mejorando';
      default:
        return 'Estable';
    }
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

  String _formatearHora(DateTime fecha) {
    return '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  String _duracionSeguimiento() {
    final inicio = widget.detecciones.first.fecha;
    final fin = widget.detecciones.last.fecha;
    final dias = fin.difference(inicio).inDays;
    if (dias == 0) return 'Mismo día';
    if (dias == 1) return '1 día';
    return '$dias días';
  }

  @override
  Widget build(BuildContext context) {
    final ultima = widget.detecciones.last;
    final colorActual = _colorFase(ultima.fase);
    final totalRegistros = widget.detecciones.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorActual.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Cabecera de la tarjeta ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorActual.withOpacity(0.08),
                  colorActual.withOpacity(0.03),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Icono de fase actual
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorActual.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _iconoFase(ultima.fase),
                        color: colorActual,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // ID y estado actual
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mazorca ${widget.idMazorca.length > 8 ? widget.idMazorca.substring(0, 8) : widget.idMazorca}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colorActual,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _nombreFase(ultima.fase),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorActual,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Botón agregar evaluación
                    IconButton(
                      onPressed: widget.onAgregar,
                      icon: const Icon(Icons.add_circle),
                      color: TemaApp.verdePrimario,
                      tooltip: 'Nueva evaluación',
                      style: IconButton.styleFrom(
                        backgroundColor: TemaApp.verdePrimario.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Estadísticas en pills
                Row(
                  children: [
                    _Pill(
                      icono: Icons.format_list_numbered,
                      texto: '$totalRegistros evaluaciones',
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      icono: Icons.schedule,
                      texto: _duracionSeguimiento(),
                      color: Colors.purple.shade600,
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      icono: _iconoTendencia(),
                      texto: _textoTendencia(),
                      color: _colorTendencia(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Confianza de la última detección ──────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Confianza actual:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ultima.confianza,
                      backgroundColor: Colors.grey.shade200,
                      color: colorActual,
                      minHeight: 7,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(ultima.confianza * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorActual,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Línea de tiempo (expandible) ───────────────────────────────
          InkWell(
            onTap: () => setState(() => _expandida = !_expandida),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.timeline, size: 18, color: TemaApp.verdePrimario),
                  const SizedBox(width: 8),
                  Text(
                    'Ver línea de tiempo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _expandida
                          ? TemaApp.verdePrimario
                          : Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expandida
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _expandida
                        ? TemaApp.verdePrimario
                        : Colors.grey.shade500,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          if (_expandida) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: _LineaDeTiempo(
                detecciones: widget.detecciones,
                colorFase: _colorFase,
                iconoFase: _iconoFase,
                nombreFase: _nombreFase,
                formatearFecha: _formatearFecha,
                formatearHora: _formatearHora,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pill de estadística ───────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;

  const _Pill({required this.icono, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Línea de tiempo visual ────────────────────────────────────────────────────

class _LineaDeTiempo extends StatelessWidget {
  final List<Deteccion> detecciones;
  final Color Function(String) colorFase;
  final IconData Function(String) iconoFase;
  final String Function(String) nombreFase;
  final String Function(DateTime) formatearFecha;
  final String Function(DateTime) formatearHora;

  const _LineaDeTiempo({
    required this.detecciones,
    required this.colorFase,
    required this.iconoFase,
    required this.nombreFase,
    required this.formatearFecha,
    required this.formatearHora,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(detecciones.length, (index) {
        final det = detecciones[index];
        final esUltimo = index == detecciones.length - 1;
        final esPrimero = index == 0;
        final color = colorFase(det.fase);
        final esUrlFirebase = det.rutaImagen.startsWith('http');

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Columna de línea + nodo ──────────────────────────────
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    // Línea superior (no para el primero)
                    if (!esPrimero)
                      Container(
                        width: 2,
                        height: 12,
                        color: Colors.grey.shade300,
                      ),
                    // Nodo del evento
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Icon(iconoFase(det.fase), color: color, size: 16),
                    ),
                    // Línea inferior (no para el último)
                    if (!esUltimo)
                      Expanded(
                        child: Container(width: 2, color: Colors.grey.shade300),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // ── Contenido del evento ─────────────────────────────────
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: esUltimo ? 0 : 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: esUltimo
                          ? color.withOpacity(0.06)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: esUltimo
                            ? color.withOpacity(0.25)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Encabezado: fase y badge "actual"
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nombreFase(det.fase),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                            if (esUltimo)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Actual',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (esPrimero && !esUltimo)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Inicial',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Fecha y hora
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatearFecha(det.fecha),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatearHora(det.fecha),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Barra de confianza
                        Row(
                          children: [
                            Text(
                              'Confianza: ',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: det.confianza,
                                  backgroundColor: Colors.grey.shade200,
                                  color: color,
                                  minHeight: 5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${(det.confianza * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),

                        // Lote si existe
                        if (det.lote != null && det.lote!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.terrain,
                                size: 12,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                det.lote!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Observaciones si existen
                        if (det.notas != null &&
                            det.notas!.isNotEmpty &&
                            det.notas != 'Seguimiento de mazorca') ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes,
                                size: 12,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  det.notas!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Imagen miniatura si existe
                        if (det.rutaImagen.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: esUrlFirebase
                                ? CachedNetworkImage(
                                    imageUrl: det.rutaImagen,
                                    height: 90,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      height: 90,
                                      color: Colors.grey.shade200,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: TemaApp.verdePrimario,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => _imagenError(),
                                  )
                                : Image.file(
                                    File(det.rutaImagen),
                                    height: 90,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _imagenError(),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _imagenError() => Container(
    height: 90,
    color: Colors.grey.shade100,
    child: Icon(
      Icons.image_not_supported,
      color: Colors.grey.shade400,
      size: 32,
    ),
  );
}

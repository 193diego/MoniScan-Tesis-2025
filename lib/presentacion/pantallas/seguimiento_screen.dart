// lib/presentacion/pantallas/seguimiento_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/deteccion.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';
import 'escaneo_screen.dart';

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

      // AGRUPAR POR idMazorca (mazorca física)
      final Map<String, List<Deteccion>> agrupado = {};
      for (var deteccion in todasDetecciones) {
        if (!agrupado.containsKey(deteccion.idMazorca)) {
          agrupado[deteccion.idMazorca] = [];
        }
        agrupado[deteccion.idMazorca]!.add(deteccion);
      }

      // Ordenar por fecha (más recientes primero)
      agrupado.forEach((key, lista) {
        lista.sort((a, b) => b.fecha.compareTo(a.fecha));
      });

      setState(() {
        _seguimientosPorMazorca = agrupado;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando seguimientos: $e');
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento de Mazorcas'),
        backgroundColor: TemaApp.verdePrimario,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarSeguimientos,
          ),
        ],
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando seguimientos...')
          : _seguimientosPorMazorca.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timeline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay seguimientos registrados',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Realiza detecciones para ver el seguimiento',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargarSeguimientos,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _seguimientosPorMazorca.length,
                itemBuilder: (context, index) {
                  final idMazorca = _seguimientosPorMazorca.keys.elementAt(
                    index,
                  );
                  final detecciones = _seguimientosPorMazorca[idMazorca]!;

                  return _TarjetaSeguimientoMazorca(
                    idMazorca: idMazorca,
                    detecciones: detecciones,
                    cedulaUsuario: widget.cedulaUsuario,
                  );
                },
              ),
            ),
    );
  }
}

class _TarjetaSeguimientoMazorca extends StatelessWidget {
  final String idMazorca;
  final List<Deteccion> detecciones;
  final String cedulaUsuario;

  const _TarjetaSeguimientoMazorca({
    required this.idMazorca,
    required this.detecciones,
    required this.cedulaUsuario,
  });

  @override
  Widget build(BuildContext context) {
    final primeraDeteccion = detecciones.first;
    final ultimaFase = primeraDeteccion.fase;
    final totalRegistros = detecciones.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mazorca ${idMazorca.substring(0, 8)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalRegistros ${totalRegistros == 1 ? 'registro' : 'registros'}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EscaneoScreen(
                          cedulaUsuario: cedulaUsuario,
                          idMazorcaSeguimiento: idMazorca,
                          grupoImagenSeguimiento: primeraDeteccion.grupoImagen,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Agregar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemaApp.verdePrimario,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ESTADO ACTUAL
            EtiquetaFase(fase: ultimaFase, tamanoTexto: 12),
            const SizedBox(height: 16),
            const Divider(),

            // TIMELINE
            ...detecciones.asMap().entries.map((entry) {
              final index = entry.key;
              final deteccion = entry.value;
              final esUltimo = index == detecciones.length - 1;

              return _ItemTimeline(
                deteccion: deteccion,
                esUltimo: esUltimo,
                esPrimero: index == 0,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ItemTimeline extends StatelessWidget {
  final Deteccion deteccion;
  final bool esUltimo;
  final bool esPrimero;

  const _ItemTimeline({
    required this.deteccion,
    required this.esUltimo,
    required this.esPrimero,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TIMELINE VISUAL
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: esPrimero ? TemaApp.verdePrimario : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              if (!esUltimo)
                Expanded(child: Container(width: 2, color: Colors.grey[300])),
            ],
          ),
          const SizedBox(width: 12),

          // CONTENIDO
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: esUltimo ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // IMAGEN PREVISUALIZACIÓN
                  if (deteccion.rutaImagen.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _construirImagen(deteccion.rutaImagen),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // INFORMACIÓN
                  Row(
                    children: [
                      EtiquetaFase(fase: deteccion.fase, tamanoTexto: 11),
                      const SizedBox(width: 8),
                      Text(
                        '${(deteccion.confianza * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatearFecha(deteccion.fecha),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),

                  // OBSERVACIONES
                  if (deteccion.notas != null &&
                      deteccion.notas!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.note, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              deteccion.notas!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
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
        ],
      ),
    );
  }

  Widget _construirImagen(String rutaImagen) {
    if (rutaImagen.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: rutaImagen,
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 120,
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => Container(
          height: 120,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, size: 40),
        ),
      );
    } else {
      return Image.file(
        File(rutaImagen),
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 120,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, size: 40),
        ),
      );
    }
  }

  String _formatearFecha(DateTime fecha) {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(fecha);

    if (diferencia.inDays == 0) {
      return 'Hoy ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}';
    } else if (diferencia.inDays == 1) {
      return 'Ayer';
    } else if (diferencia.inDays < 7) {
      return 'Hace ${diferencia.inDays} días';
    } else {
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    }
  }
}

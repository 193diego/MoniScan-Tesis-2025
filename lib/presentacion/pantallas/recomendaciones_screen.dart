// lib/presentacion/pantallas/recomendaciones_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../logica/servicios/servicio_recomendaciones.dart';
import '../../datos/modelos/recomendacion.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';

class RecomendacionesScreen extends StatefulWidget {
  final String? fase; // Opcional: si viene de una detección específica

  const RecomendacionesScreen({
    super.key,
    this.fase,
  });

  @override
  State<RecomendacionesScreen> createState() => _RecomendacionesScreenState();
}

class _RecomendacionesScreenState extends State<RecomendacionesScreen> {
  final ServicioRecomendaciones _servicio = ServicioRecomendaciones();
  
  List<Recomendacion> _recomendaciones = [];
  bool _cargando = true;
  String? _faseSeleccionada;

  @override
  void initState() {
    super.initState();
    _faseSeleccionada = widget.fase;
    _cargarRecomendaciones();
  }

  Future<void> _cargarRecomendaciones() async {
    setState(() => _cargando = true);

    try {
      final recomendaciones = _faseSeleccionada != null
          ? await _servicio.obtenerPorFase(_faseSeleccionada!)
          : await _servicio.obtenerTodas();

      setState(() {
        _recomendaciones = recomendaciones;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  void _mostrarFiltroFase() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Filtrar por Fase',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Todas',
                'Sana',
                'Fase Temprana',
                'Fase Intermedia',
                'Fase Avanzada',
                'Fase Crítica',
              ].map((fase) {
                final estaSeleccionada = fase == 'Todas'
                    ? _faseSeleccionada == null
                    : _faseSeleccionada == fase;

                return ChoiceChip(
                  label: Text(fase),
                  selected: estaSeleccionada,
                  onSelected: (selected) {
                    setState(() {
                      _faseSeleccionada = fase == 'Todas' ? null : fase;
                    });
                    Navigator.pop(context);
                    _cargarRecomendaciones();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recomendaciones'),
        actions: [
          IconButton(
            icon: Icon(
              _faseSeleccionada != null
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
            ),
            onPressed: _mostrarFiltroFase,
            tooltip: 'Filtrar por fase',
          ),
        ],
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando recomendaciones...')
          : _recomendaciones.isEmpty
              ? const MensajeVacio(
                  icono: Icons.lightbulb_outline,
                  mensaje: 'No hay recomendaciones',
                  subtitulo: 'Selecciona una fase para ver recomendaciones',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _recomendaciones.length,
                  itemBuilder: (context, index) {
                    final recomendacion = _recomendaciones[index];
                    return _TarjetaRecomendacion(
                      recomendacion: recomendacion,
                      onTap: () => _mostrarDetalle(recomendacion),
                    );
                  },
                ),
    );
  }

  void _mostrarDetalle(Recomendacion recomendacion) {
    showDialog(
      context: context,
      builder: (context) => _DialogoDetalleRecomendacion(
        recomendacion: recomendacion,
      ),
    );
  }
}

/// Tarjeta de recomendación
class _TarjetaRecomendacion extends StatelessWidget {
  final Recomendacion recomendacion;
  final VoidCallback onTap;

  const _TarjetaRecomendacion({
    required this.recomendacion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  // Prioridad
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: recomendacion.colorPrioridad.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: recomendacion.colorPrioridad,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      recomendacion.textoPrioridad,
                      style: TextStyle(
                        color: recomendacion.colorPrioridad,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Fase
                  EtiquetaFase(
                    fase: recomendacion.fase,
                    tamanoTexto: 11,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Título
              Text(
                recomendacion.titulo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Descripción
              Text(
                recomendacion.descripcion,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Número de acciones
              Row(
                children: [
                  Icon(
                    Icons.checklist,
                    size: 16,
                    color: TemaApp.verdePrimario,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${recomendacion.acciones.length} acciones recomendadas',
                    style: TextStyle(
                      fontSize: 13,
                      color: TemaApp.verdePrimario,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo de detalle de recomendación
class _DialogoDetalleRecomendacion extends StatelessWidget {
  final Recomendacion recomendacion;

  const _DialogoDetalleRecomendacion({
    required this.recomendacion,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Imagen (si existe)
            if (recomendacion.urlImagen != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: recomendacion.urlImagen!,
                  height: 180,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => const SizedBox(),
                ),
              ),

            // Contenido
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prioridad y Fase
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: recomendacion.colorPrioridad.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: recomendacion.colorPrioridad,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          recomendacion.textoPrioridad,
                          style: TextStyle(
                            color: recomendacion.colorPrioridad,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      EtiquetaFase(
                        fase: recomendacion.fase,
                        tamanoTexto: 12,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Título
                  Text(
                    recomendacion.titulo,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Descripción
                  Text(
                    recomendacion.descripcion,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Acciones
                  const Text(
                    'Acciones Recomendadas:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ...recomendacion.acciones.asMap().entries.map((entry) {
                    final index = entry.key;
                    final accion = entry.value;
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: TemaApp.verdePrimario,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              accion,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 20),

                  // Botón cerrar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
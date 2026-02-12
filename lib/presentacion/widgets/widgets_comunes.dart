// lib/presentacion/widgets/widgets_comunes.dart
import 'package:flutter/material.dart';
import '../../config/constantes.dart';
import '../../config/tema.dart';

/// Widget de carga con indicador circular
class IndicadorCarga extends StatelessWidget {
  final String mensaje;
  const IndicadorCarga({super.key, this.mensaje = 'Cargando...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: TemaApp.verdePrimario),
          const SizedBox(height: 16),
          Text(
            mensaje,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// Widget para mostrar mensaje cuando no hay datos
class MensajeVacio extends StatelessWidget {
  final IconData icono;
  final String mensaje;
  final String? subtitulo;

  const MensajeVacio({
    super.key,
    required this.icono,
    required this.mensaje,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              mensaje,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitulo!,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Campo de texto personalizado
class CampoTextoPersonalizado extends StatelessWidget {
  final TextEditingController controlador;
  final String etiqueta;
  final String? pista;
  final IconData? icono;
  final bool esContrasena;
  final TextInputType? tipoTeclado;
  final String? Function(String?)? validador;
  final int? lineasMaximas;
  final bool soloLectura;

  const CampoTextoPersonalizado({
    super.key,
    required this.controlador,
    required this.etiqueta,
    this.pista,
    this.icono,
    this.esContrasena = false,
    this.tipoTeclado,
    this.validador,
    this.lineasMaximas = 1,
    this.soloLectura = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controlador,
      obscureText: esContrasena,
      keyboardType: tipoTeclado,
      validator: validador,
      maxLines: esContrasena ? 1 : lineasMaximas,
      readOnly: soloLectura,
      decoration: InputDecoration(
        labelText: etiqueta,
        hintText: pista,
        prefixIcon: icono != null ? Icon(icono) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TemaApp.verdePrimario, width: 2),
        ),
        filled: true,
        fillColor: soloLectura ? Colors.grey[100] : Colors.white,
      ),
    );
  }
}

/// Etiqueta de fase MEJORADA - Con manejo de overflow
class EtiquetaFase extends StatelessWidget {
  final String fase;
  final double tamanoTexto;

  const EtiquetaFase({super.key, required this.fase, this.tamanoTexto = 12});

  @override
  Widget build(BuildContext context) {
    final color = Color(Constantes.obtenerColorPorClase(fase));
    final nombreDescriptivo = Constantes.obtenerNombreClase(fase);
    final icono = _obtenerIconoFase(fase);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: tamanoTexto + 2, color: Colors.white),
          const SizedBox(width: 6),
          // CORRECCIÓN: Flexible para evitar overflow
          Flexible(
            child: Text(
              nombreDescriptivo,
              style: TextStyle(
                fontSize: tamanoTexto,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow
                  .ellipsis, // Agregar puntos suspensivos si es muy largo
              maxLines: 1, // Máximo 1 línea
            ),
          ),
        ],
      ),
    );
  }

  IconData _obtenerIconoFase(String fase) {
    if (fase.contains('Sana')) return Icons.check_circle;
    if (fase.contains('Temprana')) return Icons.warning_amber;
    if (fase.contains('Intermedia')) return Icons.error;
    if (fase.contains('Avanzada')) return Icons.dangerous;
    if (fase.contains('Critica')) return Icons.cancel;
    return Icons.help;
  }
}

/// NUEVO: Widget para mostrar MÚLTIPLES etiquetas de fase
class EtiquetasFaseMultiples extends StatelessWidget {
  final List<String> fases;
  final double tamanoTexto;

  const EtiquetasFaseMultiples({
    super.key,
    required this.fases,
    this.tamanoTexto = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (fases.isEmpty) {
      return const SizedBox.shrink();
    }

    // Si solo hay una fase, mostrar etiqueta normal
    if (fases.length == 1) {
      return EtiquetaFase(fase: fases.first, tamanoTexto: tamanoTexto);
    }

    // Si hay múltiples fases, mostrar Wrap con todas las etiquetas
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: fases
          .map((fase) => EtiquetaFase(fase: fase, tamanoTexto: tamanoTexto))
          .toList(),
    );
  }
}

/// Botón principal personalizado
class BotonPrincipal extends StatelessWidget {
  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool cargando;
  final Color? color;

  const BotonPrincipal({
    super.key,
    required this.texto,
    this.onPressed,
    this.icono,
    this.cargando = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: cargando ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? TemaApp.verdePrimario,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: cargando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 22),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    texto,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tarjeta de estadística
class TarjetaEstadistica extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final Color color;

  const TarjetaEstadistica({
    super.key,
    required this.icono,
    required this.titulo,
    required this.valor,
    this.color = TemaApp.verdePrimario,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 32, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              valor,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              titulo,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Separador con texto
class SeparadorConTexto extends StatelessWidget {
  final String texto;

  const SeparadorConTexto({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            texto,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Banner de conexión MEJORADO
class BannerConexionMejorado extends StatelessWidget {
  final bool estaConectado;

  const BannerConexionMejorado({super.key, required this.estaConectado});

  @override
  Widget build(BuildContext context) {
    if (estaConectado) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.cloud_off, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            'Sin conexión - Modo offline',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

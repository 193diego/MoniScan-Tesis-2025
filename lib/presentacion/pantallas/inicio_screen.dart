import 'package:flutter/material.dart';
import '../../config/tema.dart';
import 'escaneo_screen.dart';
import 'subir_imagen_screen.dart';
import 'seguimiento_screen.dart';
import 'diagnostico_modelo_screen.dart'; // ✅ NUEVO IMPORT

/// Pantalla de inicio con diseño moderno e intuitivo
class InicioScreen extends StatelessWidget {
  final String cedulaUsuario;
  const InicioScreen({super.key, required this.cedulaUsuario});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.agriculture),
            SizedBox(width: 8),
            Text('MoniScan'),
          ],
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Bienvenido',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '¿Qué deseas hacer hoy?',
              style: TextStyle(
                fontSize: 16,
                color: TemaApp.colorTextoSecundario,
              ),
            ),
            const SizedBox(height: 32),

            // Opción 1: Escaneo en tiempo real
            _OpcionModerna(
              icono: Icons.camera_alt_rounded,
              titulo: 'Escaneo en Tiempo Real',
              descripcion: 'Detecta moniliasis con la cámara',
              color: const Color(0xFF4CAF50),
              gradiente: const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              alPresionar: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EscaneoScreen(cedulaUsuario: cedulaUsuario),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Opción 2: Analizar imagen
            _OpcionModerna(
              icono: Icons.photo_library_rounded,
              titulo: 'Analizar desde Galería',
              descripcion: 'Sube una foto para analizar',
              color: const Color(0xFF2196F3),
              gradiente: const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF42A5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              alPresionar: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SubirImagenScreen(cedulaUsuario: cedulaUsuario),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Opción 3: Seguimiento
            _OpcionModerna(
              icono: Icons.timeline_rounded,
              titulo: 'Seguimiento Activo',
              descripcion: 'Rastrea la evolución de mazorcas',
              color: const Color(0xFF9C27B0),
              gradiente: const LinearGradient(
                colors: [Color(0xFF9C27B0), Color(0xFFAB47BC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              alPresionar: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SeguimientoScreen(cedulaUsuario: cedulaUsuario),
                  ),
                );
              },
            ),

            // ✅ BOTÓN DE DIAGNÓSTICO (NUEVO)
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DiagnosticoModeloScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.bug_report, size: 20),
                label: const Text('🧪 Diagnosticar Modelo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  side: const BorderSide(color: Colors.deepPurple, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Información adicional
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TemaApp.verdeClaro.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TemaApp.verdeClaro, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: TemaApp.verdePrimario),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Todas las detecciones se guardan automáticamente con coordenadas GPS',
                      style: TextStyle(
                        fontSize: 13,
                        color: TemaApp.verdePrimario,
                      ),
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

/// Widget de opción moderna con animación y diseño mejorado
class _OpcionModerna extends StatefulWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;
  final Gradient gradiente;
  final VoidCallback alPresionar;

  const _OpcionModerna({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
    required this.gradiente,
    required this.alPresionar,
  });

  @override
  State<_OpcionModerna> createState() => _OpcionModernaState();
}

class _OpcionModernaState extends State<_OpcionModerna>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.alPresionar,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: widget.gradiente,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(
                      alpha: _isPressed ? 0.3 : 0.25,
                    ),
                    blurRadius: _isPressed ? 8 : 12,
                    offset: Offset(0, _isPressed ? 2 : 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    // Icono redondeado
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icono, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 16),
                    // Texto
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.titulo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.descripcion,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Flecha
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

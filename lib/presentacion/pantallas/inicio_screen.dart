// lib/presentacion/pantallas/inicio_screen.dart
// ✅ BOTÓN DIAGNÓSTICO COMENTADO
import 'package:flutter/material.dart';
import '../../config/tema.dart';
import 'escaneo_screen.dart';
import 'subir_imagen_screen.dart';
import 'historial_screen.dart';
import 'perfil_screen.dart';

class InicioScreen extends StatefulWidget {
  final String cedulaUsuario;

  const InicioScreen({super.key, required this.cedulaUsuario});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaApp.colorFondo,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¡Bienvenido!',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: TemaApp.verdePrimario,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Detección de Moniliasis por fase',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botón perfil
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PerfilScreen(cedulaUsuario: widget.cedulaUsuario),
                        ),
                      );
                    },
                    child: Hero(
                      tag: 'foto_perfil',
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: TemaApp.verdeClaro,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: TemaApp.verdePrimario,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: TemaApp.verdePrimario.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person,
                          color: TemaApp.verdePrimario,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // ACCIONES PRINCIPALES
              ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  children: [
                    _buildBotonPrincipal(
                      context: context,
                      titulo: 'Escanear con cámara',
                      subtitulo: 'Detección en tiempo real',
                      icono: Icons.camera_alt,
                      color: TemaApp.verdePrimario,
                      onTap: () => _navegarAEscaneo(context),
                    ),
                    const SizedBox(height: 16),
                    _buildBotonPrincipal(
                      context: context,
                      titulo: 'Subir imagen',
                      subtitulo: 'Analizar desde galería',
                      icono: Icons.photo_library,
                      color: Colors.blue.shade600,
                      onTap: () => _navegarASubirImagen(context),
                    ),
                    const SizedBox(height: 16),
                    _buildBotonPrincipal(
                      context: context,
                      titulo: 'Historial',
                      subtitulo: 'Ver detecciones guardadas',
                      icono: Icons.history,
                      color: Colors.orange.shade600,
                      onTap: () => _navegarAHistorial(context),
                    ),

                    // ✅ BOTÓN DIAGNÓSTICO COMENTADO
                    // const SizedBox(height: 16),
                    // _buildBotonPrincipal(
                    //   context: context,
                    //   titulo: 'Diagnóstico del modelo',
                    //   subtitulo: 'Verificar funcionamiento',
                    //   icono: Icons.analytics,
                    //   color: Colors.purple.shade600,
                    //   onTap: () {
                    //     // Navegar a pantalla de diagnóstico
                    //   },
                    // ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // INFO CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      TemaApp.verdeClaro.withOpacity(0.3),
                      TemaApp.verdeSecundario.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: TemaApp.verdeSecundario.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.eco,
                        color: TemaApp.verdePrimario,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detección de Moniliasis',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: TemaApp.verdePrimario,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Detección de Moniliasis en cacao CCN-51 por fase',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotonPrincipal({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icono, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _navegarAEscaneo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EscaneoScreen(
          usuarioId: widget.cedulaUsuario,
          onVolverInicio: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _navegarASubirImagen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SubirImagenScreen(cedulaUsuario: widget.cedulaUsuario),
      ),
    );
  }

  void _navegarAHistorial(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            HistorialScreen(cedulaUsuario: widget.cedulaUsuario),
      ),
    );
  }
}

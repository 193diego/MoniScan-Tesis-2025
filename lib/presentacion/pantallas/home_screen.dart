// lib/presentacion/pantallas/home_screen.dart
import 'package:flutter/material.dart';
import 'package:elegant_nav_bar/elegant_nav_bar.dart';
import '../../logica/servicios/servicio_conectividad.dart';
import 'inicio_screen.dart';
import 'historial_screen.dart';
import 'mapa_screen.dart';
import 'perfil_screen.dart';

class HomeScreen extends StatefulWidget {
  final String cedulaUsuario;

  const HomeScreen({super.key, required this.cedulaUsuario});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _indiceActual = 0;
  late PageController _pageController;
  late List<Widget> _pantallas;
  final ServicioConectividad _conectividad = ServicioConectividad();
  bool _estaConectado = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _indiceActual);
    _pantallas = [
      InicioScreen(cedulaUsuario: widget.cedulaUsuario),
      HistorialScreen(cedulaUsuario: widget.cedulaUsuario),
      MapaScreen(cedulaUsuario: widget.cedulaUsuario),
      PerfilScreen(cedulaUsuario: widget.cedulaUsuario),
    ];

    // Escuchar cambios de conectividad
    _conectividad.estadoConexion.listen((conectado) {
      if (mounted) {
        setState(() {
          _estaConectado = conectado;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _indiceActual = index;
    });
  }

  void _onNavBarTap(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          /// Banner de conexión MEJORADO
          if (!_estaConectado) _construirBannerOffline(),

          /// Contenido principal
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              // CRÍTICO: Deshabilitar swipe en mapa (índice 2)
              physics: _indiceActual == 2
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              children: _pantallas,
            ),
          ),
        ],
      ),
      bottomNavigationBar: ElegantBottomNavigationBar(
        currentIndex: _indiceActual,
        onTap: _onNavBarTap,
        items: [
          NavigationItem(
            label: 'Inicio',
            iconWidget: Icon(
              _indiceActual == 0 ? Icons.home : Icons.home_outlined,
              size: _indiceActual == 0 ? 28 : 24,
            ),
          ),
          NavigationItem(
            label: 'Historial',
            iconWidget: Icon(
              _indiceActual == 1 ? Icons.history : Icons.history_outlined,
              size: _indiceActual == 1 ? 28 : 24,
            ),
          ),
          NavigationItem(
            label: 'Mapa',
            iconWidget: Icon(
              _indiceActual == 2 ? Icons.map : Icons.map_outlined,
              size: _indiceActual == 2 ? 28 : 24,
            ),
          ),
          NavigationItem(
            label: 'Perfil',
            iconWidget: Icon(
              _indiceActual == 3 ? Icons.person : Icons.person_outline,
              size: _indiceActual == 3 ? 28 : 24,
            ),
          ),
        ],
        indicatorPosition: IndicatorPosition.bottom,
        indicatorShape: IndicatorShape.dot,
        isFloating: true,
        floatingMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        floatingBorderRadius: 24,
      ),
    );
  }

  /// Widget de banner offline mejorado
  Widget _construirBannerOffline() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.orange,
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cloud_off, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(
              'Sin conexión - Modo offline',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

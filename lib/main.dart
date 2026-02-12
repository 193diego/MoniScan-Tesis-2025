import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'config/tema.dart';
import 'config/constantes.dart';
import 'presentacion/pantallas/login_firebase_screen.dart';
import 'logica/servicios/servicio_conectividad.dart';
import 'logica/servicios/servicio_sincronizacion.dart';
import 'utils/manejador_errores.dart';

void main() async {
  // Asegurar inicialización de Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar manejador de errores global
  ManejadorErrores.inicializar();

  // Configurar orientación
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configurar barra de estado
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Inicializar Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase inicializado correctamente');
  } catch (e) {
    debugPrint('❌ Error inicializando Firebase: $e');
  }

  // Inicializar servicios globales
  try {
    await _inicializarServicios();
    debugPrint('✅ Servicios globales inicializados');
  } catch (e) {
    debugPrint('❌ Error inicializando servicios: $e');
  }

  // Ejecutar app
  runApp(const MoniScanApp());
}

/// Inicializar servicios globales
Future<void> _inicializarServicios() async {
  // Inicializar servicio de conectividad
  final conectividad = ServicioConectividad();
  await conectividad.inicializar();

  // Inicializar sincronización automática
  final sincronizacion = ServicioSincronizacion();
  sincronizacion.inicializarSincronizacionAutomatica();

  debugPrint('🔄 Sincronización automática activada');
}

class MoniScanApp extends StatelessWidget {
  const MoniScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Constantes.nombreApp,
      debugShowCheckedModeBanner: false,
      theme: TemaApp.obtenerTemaClaro(),

      // Manejador global de navegación con errores
      builder: (context, child) {
        // Configurar texto escalable
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaleFactor: MediaQuery.of(
              context,
            ).textScaleFactor.clamp(0.8, 1.2),
          ),
          child: child ?? const SizedBox(),
        );
      },

      // Pantalla inicial
      home: const LoginFirebaseScreen(),

      // Configuración de tema
      themeMode: ThemeMode.light,
    );
  }
}

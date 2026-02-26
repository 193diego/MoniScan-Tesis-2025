// lib/main.dart
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
  WidgetsFlutterBinding.ensureInitialized();

  ManejadorErrores.inicializar();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase inicializado correctamente');
  } catch (e) {
    debugPrint('❌ Error inicializando Firebase: $e');
  }

  try {
    await _inicializarServicios();
    debugPrint('✅ Servicios globales inicializados');
  } catch (e) {
    debugPrint('❌ Error inicializando servicios: $e');
  }

  runApp(const MoniScanApp());
}

Future<void> _inicializarServicios() async {
  final conectividad = ServicioConectividad();
  await conectividad.inicializar();

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

      builder: (context, child) {
        // ✅ CORRECCIÓN: textScaler reemplaza textScaleFactor (deprecated desde v3.12)
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
            ),
          ),
          child: child ?? const SizedBox(),
        );
      },

      home: const LoginFirebaseScreen(),
      themeMode: ThemeMode.light,
    );
  }
}

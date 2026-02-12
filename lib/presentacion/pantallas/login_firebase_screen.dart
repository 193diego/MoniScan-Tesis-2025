import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/tema.dart';
import '../../config/constantes.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/usuario.dart' as local_models;
import '../../logica/servicios/servicio_sincronizacion.dart';
import '../widgets/widgets_comunes.dart';
import 'home_screen.dart';

class LoginFirebaseScreen extends StatefulWidget {
  const LoginFirebaseScreen({super.key});

  @override
  State<LoginFirebaseScreen> createState() => _LoginFirebaseScreenState();
}

class _LoginFirebaseScreenState extends State<LoginFirebaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controladorEmail = TextEditingController();
  final _controladorContrasena = TextEditingController();
  final _sincronizacion = ServicioSincronizacion();
  final _baseDatos = BaseDatosHelper();

  bool _cargando = false;
  bool _ocultarContrasena = true;
  bool _verificandoSesion = true;

  @override
  void initState() {
    super.initState();
    _verificarSesionExistente();
  }

  /// Verificar si ya existe una sesión activa
  Future<void> _verificarSesionExistente() async {
    try {
      final usuarioFirebase = FirebaseAuth.instance.currentUser;

      if (usuarioFirebase != null) {
        // Usuario ya autenticado, obtener datos
        final usuarioLocal = await _obtenerYSincronizarUsuario(
          usuarioFirebase.uid,
        );

        if (usuarioLocal != null && mounted) {
          await _navegarAHome(usuarioLocal.cedula);
        } else {
          // Datos inconsistentes, cerrar sesión
          await FirebaseAuth.instance.signOut();
          setState(() => _verificandoSesion = false);
        }
      } else {
        setState(() => _verificandoSesion = false);
      }
    } catch (e) {
      debugPrint('❌ Error verificando sesión: $e');
      setState(() => _verificandoSesion = false);
    }
  }

  /// Iniciar sesión con email y contraseña
  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final email = _controladorEmail.text.trim();
      final contrasena = _controladorContrasena.text.trim();

      // 1. Autenticar con Firebase
      final credencial = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: contrasena,
      );

      final uid = credencial.user!.uid;

      // 2. Obtener documento worker
      final docSnapshot = await FirebaseFirestore.instance
          .collection('workers')
          .doc(uid)
          .get();

      if (!docSnapshot.exists) {
        await FirebaseAuth.instance.signOut();
        _mostrarError(
          'Usuario no registrado como trabajador. Contacta al administrador.',
        );
        return;
      }

      final workerData = docSnapshot.data()!;

      // 3. Verificar estado activo
      if (workerData['status'] != 'Activo') {
        await FirebaseAuth.instance.signOut();
        _mostrarError('Tu cuenta no está activa. Contacta al administrador.');
        return;
      }

      // 4. Guardar en SQLite local
      final usuarioLocal = local_models.Usuario(
        cedula: workerData['cedula'] ?? '',
        nombres: workerData['nombres'] ?? workerData['name'] ?? '',
        apellidos: workerData['apellidos'] ?? '',
        correo: email,
        direccion: workerData['direccion'],
        rutaFoto: workerData['fotoUrl'],
        fechaRegistro:
            (workerData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

      await _baseDatos.insertarUsuario(usuarioLocal);

      // 5. ✨ SINCRONIZACIÓN INICIAL Firebase → SQLite
      debugPrint('🔄 Iniciando sincronización inicial...');
      await _sincronizacion.sincronizarDesdeFirebase();

      // 6. Sincronizar detecciones pendientes en background (SQLite → Firebase)
      _sincronizacion.sincronizarTodo().catchError((e) {
        debugPrint('⚠️ Error sincronizando pendientes: $e');
      });

      // 7. Navegar a Home
      if (mounted) await _navegarAHome(usuarioLocal.cedula);
    } on FirebaseAuthException catch (e) {
      _manejarErrorAuth(e);
    } catch (e) {
      _mostrarError('Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Obtener usuario desde Firestore y sincronizar localmente

  Future<local_models.Usuario?> _obtenerYSincronizarUsuario(String uid) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('workers')
          .doc(uid)
          .get();

      if (!docSnapshot.exists) return null;

      final data = docSnapshot.data()!;

      // Verificar estado
      if (data['status'] != 'Activo') {
        await FirebaseAuth.instance.signOut();
        return null;
      }

      // ✅ MAPEO CORRECTO: Extraer nombres y apellidos del campo "name"
      final nombreCompleto = data['name'] as String? ?? '';
      final partesNombre = nombreCompleto.split(' ');

      final nombres = partesNombre.isNotEmpty ? partesNombre.first : '';
      final apellidos = partesNombre.length > 1
          ? partesNombre.skip(1).join(' ')
          : '';

      final usuario = local_models.Usuario(
        cedula: data['cedula'] ?? '',
        nombres: nombres,
        apellidos: apellidos,
        correo: data['email'] ?? '',
        telefono: data['phone'] ?? '',
        direccion: data['address'],
        rol: data['role'],
        rutaFoto: data['avatar'],
        fechaRegistro:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

      await _baseDatos.insertarUsuario(usuario);
      return usuario;
    } catch (e) {
      debugPrint('❌ Error obteniendo usuario: $e');
      return null;
    }
  }

  /// Navegar a pantalla principal
  Future<void> _navegarAHome(String cedula) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cedula_usuario', cedula);
    await prefs.setBool('sesion_activa', true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(cedulaUsuario: cedula)),
    );
  }

  /// Manejar errores de autenticación
  void _manejarErrorAuth(FirebaseAuthException e) {
    String mensaje;

    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        mensaje = 'Credenciales incorrectas';
        break;
      case 'user-not-found':
        mensaje = 'Usuario no encontrado';
        break;
      case 'user-disabled':
        mensaje = 'Esta cuenta ha sido deshabilitada';
        break;
      case 'too-many-requests':
        mensaje = 'Demasiados intentos. Intenta más tarde';
        break;
      case 'network-request-failed':
        mensaje = 'Error de conexión. Verifica tu internet';
        break;
      case 'invalid-email':
        mensaje = 'Correo electrónico inválido';
        break;
      default:
        mensaje = 'Error de autenticación: ${e.message}';
    }

    _mostrarError(mensaje);
  }

  /// Mostrar mensaje de error
  void _mostrarError(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _controladorEmail.dispose();
    _controladorContrasena.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoSesion) {
      return const Scaffold(
        body: IndicadorCarga(mensaje: 'Verificando sesión...'),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: TemaApp.degradadoVerde),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.agriculture,
                      size: 80,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      Constantes.nombreApp,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Detección de Moniliasis en Cacao',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // Formulario
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Bienvenido',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ingresa tus credenciales para continuar',
                            style: TextStyle(
                              fontSize: 14,
                              color: TemaApp.colorTextoSecundario,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Email
                          TextFormField(
                            controller: _controladorEmail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Correo Electrónico',
                              hintText: 'ejemplo@correo.com',
                              prefixIcon: Icon(Icons.email),
                            ),
                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Por favor ingresa tu correo';
                              }
                              if (!valor.contains('@')) {
                                return 'Correo inválido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Contraseña
                          TextFormField(
                            controller: _controladorContrasena,
                            obscureText: _ocultarContrasena,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _iniciarSesion(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              hintText: 'Ingresa tu contraseña',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _ocultarContrasena
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () => setState(
                                  () =>
                                      _ocultarContrasena = !_ocultarContrasena,
                                ),
                              ),
                            ),
                            validator: (valor) {
                              if (valor == null || valor.isEmpty) {
                                return 'Por favor ingresa tu contraseña';
                              }
                              if (valor.length < 6) {
                                return 'La contraseña debe tener al menos 6 caracteres';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Botón de login
                          if (_cargando)
                            const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  TemaApp.verdePrimario,
                                ),
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: _iniciarSesion,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  'Iniciar Sesión',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Aviso
                          Center(
                            child: Text(
                              'Solo trabajadores autorizados\nContacta al administrador para obtener acceso',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

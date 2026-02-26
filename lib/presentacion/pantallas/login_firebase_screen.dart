// lib/presentacion/pantallas/login_firebase_screen.dart
// ✅ VERSIÓN FINAL CORREGIDA - Alineada con PROMPT_MAESTRO_Web y movil.pdf
// ✅ Incluye recuperación de contraseña con Firebase Authentication
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
        final usuarioLocal = await _obtenerYSincronizarUsuario(
          usuarioFirebase.uid,
        );

        if (usuarioLocal != null && mounted) {
          // ✅ HomeScreen solo requiere cedulaUsuario según home_screen.dart
          await _navegarAHome(cedula: usuarioLocal.cedula);
        } else {
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
  /// ✅ CORRECCIÓN CRÍTICA 1: Usa colección 'usuarios' (NO 'workers')
  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    try {
      final email = _controladorEmail.text.trim();
      final contrasena = _controladorContrasena.text.trim();

      // 1. Autenticar con Firebase Authentication
      final credencial = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: contrasena,
      );

      final uid = credencial.user!.uid;

      // 2. ✅ CORRECCIÓN CRÍTICA: Consultar colección 'usuarios' (ERA 'workers')
      final docSnapshot = await FirebaseFirestore.instance
          .collection('usuarios') // ← CORRECTO según PROMPT_MAESTRO
          .doc(uid) // El documento tiene el mismo ID que el UID
          .get();

      if (!docSnapshot.exists) {
        await FirebaseAuth.instance.signOut();
        _mostrarError(
          'Usuario no registrado en el sistema. Contacta a la administradora.',
        );
        return;
      }

      final workerData = docSnapshot.data()!;

      // 3. ✅ CORRECCIÓN: Verificar campo 'activo' boolean (ERA 'status' string)
      if (workerData['activo'] != true) {
        await FirebaseAuth.instance.signOut();
        _mostrarError(
          'Tu cuenta está desactivada. Contacta a la administradora.',
        );
        return;
      }

      // ✅ CORRECCIÓN: Usar campo 'nombreCompleto' (ERA 'name')
      final nombreCompleto = workerData['nombreCompleto'] as String? ?? '';
      final cedula = workerData['cedula'] as String? ?? '';
      final rol = workerData['rol'] as String? ?? 'trabajador';

      // 4. Guardar en SQLite local
      final partesNombre = nombreCompleto.split(' ');
      final nombres = partesNombre.isNotEmpty ? partesNombre.first : '';
      final apellidos = partesNombre.length > 1
          ? partesNombre.skip(1).join(' ')
          : '';

      final usuarioLocal = local_models.Usuario(
        cedula: cedula,
        nombres: nombres,
        apellidos: apellidos,
        correo: email,
        telefono: workerData['telefono'] as String?,
        direccion: workerData['direccion'] as String?,
        rol: rol,
        rutaFoto: workerData['fotoPerfilURL'] as String?, // ← ERA 'fotoUrl'
        fechaRegistro:
            (workerData['creadoEn'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

      await _baseDatos.insertarUsuario(usuarioLocal);

      // 5. Sincronización inicial Firebase → SQLite
      debugPrint('🔄 Iniciando sincronización inicial...');
      await _sincronizacion.sincronizarDesdeFirebase();

      // 6. Sincronizar detecciones pendientes en background
      _sincronizacion.sincronizarTodo().catchError((e) {
        debugPrint('⚠️ Error sincronizando pendientes: $e');
      });

      // 7. ✅ Navegar a Home pasando SOLO cedulaUsuario
      if (mounted) {
        await _navegarAHome(cedula: cedula);
      }
    } on FirebaseAuthException catch (e) {
      String mensaje;
      switch (e.code) {
        case 'user-not-found':
          mensaje = 'No existe una cuenta con este correo';
          break;
        case 'wrong-password':
          mensaje = 'Contraseña incorrecta';
          break;
        case 'invalid-email':
          mensaje = 'Formato de correo inválido';
          break;
        case 'user-disabled':
          mensaje = 'Esta cuenta ha sido desactivada';
          break;
        case 'too-many-requests':
          mensaje = 'Demasiados intentos. Intenta más tarde';
          break;
        default:
          mensaje = 'Error de autenticación: ${e.message}';
      }
      _mostrarError(mensaje);
    } catch (e) {
      debugPrint('❌ Error en login: $e');
      _mostrarError('Error al iniciar sesión: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// ✅ NUEVO: Recuperar contraseña con Firebase Authentication
  /// Según PROMPT_MAESTRO Web: Firebase maneja esto automáticamente
  Future<void> _recuperarContrasena() async {
    final email = _controladorEmail.text.trim();

    if (email.isEmpty) {
      _mostrarError('Por favor ingresa tu correo electrónico');
      return;
    }

    // Validar formato de email
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _mostrarError('El formato del correo es inválido');
      return;
    }

    // Diálogo de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email_outlined, color: TemaApp.verdePrimario),
            SizedBox(width: 12),
            Text('Recuperar Contraseña'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se enviará un correo electrónico a:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TemaApp.verdePrimario,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Revisa tu bandeja de entrada y spam',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaApp.verdePrimario,
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _cargando = true);

    try {
      // ✅ Firebase Authentication envía el correo automáticamente
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (mounted) {
        _mostrarExito(
          '✅ Correo enviado\n\n'
          'Revisa tu bandeja de entrada en $email.\n'
          'Sigue las instrucciones para restablecer tu contraseña.',
        );
      }
    } on FirebaseAuthException catch (e) {
      String mensaje;
      switch (e.code) {
        case 'user-not-found':
          mensaje = 'No existe una cuenta con este correo';
          break;
        case 'invalid-email':
          mensaje = 'Formato de correo inválido';
          break;
        default:
          mensaje = 'Error al enviar correo: ${e.message}';
      }
      _mostrarError(mensaje);
    } catch (e) {
      _mostrarError('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<local_models.Usuario?> _obtenerYSincronizarUsuario(String uid) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('usuarios') // ✅ CORRECTO
          .doc(uid)
          .get();

      if (!docSnapshot.exists) return null;

      final data = docSnapshot.data()!;
      final nombreCompleto = data['nombreCompleto'] as String? ?? '';
      final cedula = data['cedula'] as String? ?? '';

      final partesNombre = nombreCompleto.split(' ');
      final nombres = partesNombre.isNotEmpty ? partesNombre.first : '';
      final apellidos = partesNombre.length > 1
          ? partesNombre.skip(1).join(' ')
          : '';

      final usuario = local_models.Usuario(
        cedula: cedula,
        nombres: nombres,
        apellidos: apellidos,
        correo: data['correo'] as String? ?? '',
        telefono: data['telefono'] as String?,
        direccion: data['direccion'] as String?,
        rol: data['rol'] as String? ?? 'trabajador',
        rutaFoto: data['fotoPerfilURL'] as String?,
        fechaRegistro:
            (data['creadoEn'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

      await _baseDatos.insertarUsuario(usuario);
      return usuario;
    } catch (e) {
      debugPrint('❌ Error obteniendo usuario: $e');
      return null;
    }
  }

  /// ✅ HomeScreen solo acepta cedulaUsuario según la estructura actual
  Future<void> _navegarAHome({required String cedula}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cedula', cedula);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(cedulaUsuario: cedula)),
      );
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensaje)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: TemaApp.verdeSecundario),
            SizedBox(width: 12),
            Text('Correo Enviado'),
          ],
        ),
        content: Text(mensaje),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemaApp.verdePrimario,
            ),
            child: const Text('Entendido'),
          ),
        ],
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
        backgroundColor: Colors.white,
        body: IndicadorCarga(mensaje: 'Verificando sesión...'),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: TemaApp.verdePrimario.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.agriculture,
                      size: 60,
                      color: TemaApp.verdePrimario,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Título
                  const Text(
                    Constantes.nombreApp,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: TemaApp.verdePrimario,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Detección de Moniliasis en Cacao',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 40),

                  // Campo Email
                  CampoTextoPersonalizado(
                    controlador: _controladorEmail,
                    etiqueta: 'Correo Electrónico',
                    pista: 'tu.correo@ejemplo.com',
                    icono: Icons.email_outlined,
                    tipoTeclado: TextInputType.emailAddress,
                    validador: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Ingresa tu correo';
                      }
                      if (!valor.contains('@')) {
                        return 'Formato de correo inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Campo Contraseña
                  TextFormField(
                    controller: _controladorContrasena,
                    obscureText: _ocultarContrasena,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _ocultarContrasena
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(
                            () => _ocultarContrasena = !_ocultarContrasena,
                          );
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Ingresa tu contraseña';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // ✅ BOTÓN RECUPERAR CONTRASEÑA
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _cargando ? null : _recuperarContrasena,
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(
                          fontSize: 14,
                          color: TemaApp.verdePrimario,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Botón Iniciar Sesión
                  BotonPrincipal(
                    texto: 'Iniciar Sesión',
                    icono: Icons.login,
                    cargando: _cargando,
                    onPressed: _iniciarSesion,
                  ),
                  const SizedBox(height: 32),

                  // Nota informativa
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Si no tienes cuenta, contacta a la administradora',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

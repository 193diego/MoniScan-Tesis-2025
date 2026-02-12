// lib/presentacion/pantallas/perfil_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../datos/local/base_datos_helper.dart';
import '../../datos/modelos/usuario.dart';
import '../../config/tema.dart';
import '../widgets/widgets_comunes.dart';
import 'login_firebase_screen.dart';

class PerfilScreen extends StatefulWidget {
  final String cedulaUsuario;
  const PerfilScreen({super.key, required this.cedulaUsuario});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final BaseDatosHelper _bd = BaseDatosHelper();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();

  Usuario? _usuario;
  Map<String, dynamic>? _datosFirestore;

  bool _cargando = true;
  bool _subiendoFoto = false;
  bool _guardando = false;

  String? _urlFotoActual;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    try {
      final usuario = await _bd.obtenerUsuarioPorCedula(widget.cedulaUsuario);
      final uid = _auth.currentUser?.uid;

      Map<String, dynamic>? datosFirestore;
      String? urlFoto;

      if (uid != null) {
        final doc = await _firestore.collection('workers').doc(uid).get();
        if (doc.exists) {
          datosFirestore = doc.data();

          // EXTRAER URL DE FOTO
          urlFoto = datosFirestore?['avatar'] as String?;

          _nombreController.text = datosFirestore?['name'] ?? '';
          _telefonoController.text = datosFirestore?['phone'] ?? '';
          _direccionController.text = datosFirestore?['address'] ?? '';
        }
      }

      if (!mounted) return;

      setState(() {
        _usuario = usuario;
        _datosFirestore = datosFirestore;
        _urlFotoActual = urlFoto;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando perfil: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarFoto() async {
    if (_subiendoFoto) return;

    final ImagePicker picker = ImagePicker();
    final XFile? imagen = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (imagen == null) return;

    setState(() => _subiendoFoto = true);

    try {
      final uid = _auth.currentUser!.uid;
      final file = File(imagen.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final rutaStorage = 'perfiles/$uid/perfil_$timestamp.jpg';
      debugPrint('📤 Subiendo foto a: $rutaStorage');

      final storageRef = _storage.ref().child(rutaStorage);

      // Invalidar caché anterior
      if (_urlFotoActual != null && _urlFotoActual!.isNotEmpty) {
        await CachedNetworkImage.evictFromCache(_urlFotoActual!);
      }

      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('✅ Foto subida: $downloadUrl');

      // Actualizar Firestore
      await _firestore.collection('workers').doc(uid).update({
        'avatar': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Actualizar SQLite
      if (_usuario != null) {
        final usuarioActualizado = _usuario!.copiarCon(rutaFoto: downloadUrl);
        await _bd.actualizarUsuario(usuarioActualizado);
      }

      // Recargar datos
      await _cargarDatos();

      if (mounted) _mostrarMensaje('✅ Foto actualizada correctamente');
    } catch (e) {
      debugPrint('❌ Error subiendo foto: $e');
      if (mounted)
        _mostrarError('Error al actualizar la foto: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _guardarCambios() async {
    if (_guardando) return;

    setState(() => _guardando = true);

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Usuario no autenticado');

      await _firestore.collection('workers').doc(uid).update({
        'name': _nombreController.text.trim(),
        'phone': _telefonoController.text.trim(),
        'address': _direccionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (_usuario != null) {
        final usuarioActualizado = _usuario!.copiarCon(
          nombres: _nombreController.text.trim(),
          direccion: _direccionController.text.trim(),
        );
        await _bd.actualizarUsuario(usuarioActualizado);
      }

      if (mounted) {
        _mostrarMensaje('✅ Perfil actualizado correctamente');
        await _cargarDatos();
      }
    } catch (e) {
      debugPrint('❌ Error guardando cambios: $e');
      if (mounted) _mostrarError('Error al guardar: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginFirebaseScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Error cerrando sesión: $e');
      if (mounted) _mostrarError('Error al cerrar sesión');
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
    );
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        centerTitle: true,
        backgroundColor: TemaApp.verdePrimario,
        elevation: 0,
      ),
      body: _cargando
          ? const IndicadorCarga(mensaje: 'Cargando perfil...')
          : _usuario == null
          ? const MensajeVacio(
              icono: Icons.error,
              mensaje: 'Error al cargar perfil',
            )
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // HEADER CON DEGRADADO
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: TemaApp.degradadoVerde,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          // AVATAR
                          Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Colors.white,
                                  backgroundImage:
                                      _urlFotoActual != null &&
                                          _urlFotoActual!.isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          _urlFotoActual!,
                                        )
                                      : null,
                                  child:
                                      _urlFotoActual == null ||
                                          _urlFotoActual!.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: TemaApp.verdePrimario,
                                        )
                                      : null,
                                ),
                              ),
                              if (_subiendoFoto)
                                Positioned.fill(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _subiendoFoto ? null : _cambiarFoto,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.2,
                                          ),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: TemaApp.verdePrimario,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _datosFirestore?['name'] ?? 'Usuario',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _datosFirestore?['email'] ?? '',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // CONTENIDO
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // INFORMACIÓN FIJA
                          const Text(
                            'Información Fija',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoCard(
                            Icons.badge,
                            'Cédula',
                            _datosFirestore?['cedula'] ?? _usuario!.cedula,
                          ),
                          _buildInfoCard(
                            Icons.work,
                            'Rol',
                            _datosFirestore?['role'] ?? 'N/A',
                          ),
                          _buildInfoCard(
                            Icons.verified,
                            'Estado',
                            _datosFirestore?['status'] ?? 'N/A',
                          ),

                          const SizedBox(height: 32),

                          // INFORMACIÓN EDITABLE
                          const Text(
                            'Información Editable',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          CampoTextoPersonalizado(
                            controlador: _nombreController,
                            etiqueta: 'Nombre Completo *',
                            pista: 'Ingresa tu nombre',
                            icono: Icons.person,
                          ),
                          const SizedBox(height: 16),

                          CampoTextoPersonalizado(
                            controlador: _telefonoController,
                            etiqueta: 'Teléfono',
                            pista: 'Ej: 0987654321',
                            icono: Icons.phone,
                            tipoTeclado: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),

                          CampoTextoPersonalizado(
                            controlador: _direccionController,
                            etiqueta: 'Dirección',
                            pista: 'Ingresa tu dirección',
                            icono: Icons.home,
                            lineasMaximas: 2,
                          ),
                          const SizedBox(height: 24),

                          // BOTÓN GUARDAR
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _guardando ? null : _guardarCambios,
                              icon: _guardando
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(
                                _guardando ? 'Guardando...' : 'Guardar Cambios',
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                backgroundColor: TemaApp.verdePrimario,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // NOTA
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Solo puedes cambiar tu foto, nombre, teléfono y dirección. Para otros cambios, contacta al administrador.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // BOTÓN CERRAR SESIÓN
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _cerrarSesion,
                              icon: const Icon(Icons.logout),
                              label: const Text('Cerrar Sesión'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
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

  Widget _buildInfoCard(IconData icono, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(icono, size: 24, color: TemaApp.verdePrimario),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

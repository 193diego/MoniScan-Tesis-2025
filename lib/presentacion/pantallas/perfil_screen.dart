// lib/presentacion/pantallas/perfil_screen.dart
// ✅ CON BOTÓN CERRAR SESIÓN Y ANIMACIONES
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/tema.dart';

class PerfilScreen extends StatefulWidget {
  final String cedulaUsuario;

  const PerfilScreen({super.key, required this.cedulaUsuario});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _cargando = true;
  bool _editando = false;
  bool _subiendoFoto = false;

  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();

  Map<String, dynamic>? _datosUsuario;
  String? _fotoPerfilUrl;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    setState(() => _cargando = true);

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        _mostrarError('Usuario no autenticado');
        return;
      }

      final doc = await _firestore.collection('usuarios').doc(uid).get();

      if (!doc.exists) {
        _mostrarError('Usuario no encontrado en Firestore');
        return;
      }

      final datos = doc.data()!;

      setState(() {
        _datosUsuario = datos;
        _fotoPerfilUrl = datos['fotoPerfilURL'] as String?;
        _nombreController.text = datos['nombreCompleto'] ?? '';
        _telefonoController.text = datos['telefono'] ?? '';
        _direccionController.text = datos['direccion'] ?? '';
        _cargando = false;
      });

      _animationController.forward();
    } catch (e) {
      debugPrint('❌ Error cargando perfil: $e');
      if (mounted) {
        setState(() => _cargando = false);
        _mostrarError('Error al cargar perfil: $e');
      }
    }
  }

  Future<void> _cambiarFotoPerfil() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? imagen = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (imagen == null) return;

      setState(() => _subiendoFoto = true);

      final uid = _auth.currentUser!.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final rutaStorage = 'perfiles/$uid/perfil_$timestamp.jpg';

      final storageRef = _storage.ref().child(rutaStorage);
      await storageRef.putFile(File(imagen.path));
      final downloadUrl = await storageRef.getDownloadURL();

      await _firestore.collection('usuarios').doc(uid).update({
        'fotoPerfilURL': downloadUrl,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      setState(() {
        _fotoPerfilUrl = downloadUrl;
        _subiendoFoto = false;
      });

      _mostrarMensaje('✅ Foto actualizada correctamente');
    } catch (e) {
      debugPrint('❌ Error cambiando foto: $e');
      setState(() => _subiendoFoto = false);
      _mostrarError('Error al cambiar foto: $e');
    }
  }

  Future<void> _guardarCambios() async {
    try {
      final uid = _auth.currentUser!.uid;

      await _firestore.collection('usuarios').doc(uid).update({
        'nombreCompleto': _nombreController.text.trim(),
        'telefono': _telefonoController.text.trim(),
        'direccion': _direccionController.text.trim(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      setState(() => _editando = false);
      _mostrarMensaje('✅ Perfil actualizado correctamente');
      _cargarDatosUsuario();
    } catch (e) {
      debugPrint('❌ Error guardando cambios: $e');
      _mostrarError('Error al guardar: $e');
    }
  }

  // ✅ CERRAR SESIÓN
  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 12),
            Text('Cerrar sesión'),
          ],
        ),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: TemaApp.verdeSecundario,
      ),
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nombreController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaApp.colorFondo,
      appBar: AppBar(
        title: const Text(
          'Mi Perfil',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: TemaApp.verdePrimario,
        elevation: 0,
        actions: [
          if (!_editando && !_cargando)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'Editar perfil',
              onPressed: () => setState(() => _editando = true),
            ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: TemaApp.verdePrimario),
                  SizedBox(height: 16),
                  Text('Cargando perfil...'),
                ],
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // HEADER CON FOTO
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: TemaApp.verdePrimario,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                      ),
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Stack(
                            children: [
                              Hero(
                                tag: 'foto_perfil',
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: CircleAvatar(
                                    radius: 70,
                                    backgroundColor: Colors.white,
                                    child: _subiendoFoto
                                        ? const CircularProgressIndicator(
                                            color: TemaApp.verdePrimario,
                                          )
                                        : _fotoPerfilUrl != null
                                        ? ClipOval(
                                            child: CachedNetworkImage(
                                              imageUrl: _fotoPerfilUrl!,
                                              width: 140,
                                              height: 140,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  const CircularProgressIndicator(
                                                    color:
                                                        TemaApp.verdePrimario,
                                                  ),
                                              errorWidget:
                                                  (context, url, error) => Icon(
                                                    Icons.person,
                                                    size: 70,
                                                    color: Colors.grey.shade400,
                                                  ),
                                            ),
                                          )
                                        : Icon(
                                            Icons.person,
                                            size: 70,
                                            color: Colors.grey.shade400,
                                          ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _subiendoFoto
                                      ? null
                                      : _cambiarFotoPerfil,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: TemaApp.verdePrimario,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _datosUsuario?['nombreCompleto'] ?? 'Sin nombre',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _datosUsuario?['correo'] ?? 'Sin correo',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildInfoCard(
                            icon: Icons.badge,
                            titulo: 'Cédula',
                            contenido: _datosUsuario?['cedula'] ?? 'N/A',
                            editable: false,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoCard(
                            icon: Icons.person_outline,
                            titulo: 'Nombre completo',
                            contenido: _nombreController.text,
                            editable: true,
                            controller: _nombreController,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoCard(
                            icon: Icons.email_outlined,
                            titulo: 'Correo electrónico',
                            contenido: _datosUsuario?['correo'] ?? 'N/A',
                            editable: false,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoCard(
                            icon: Icons.phone_outlined,
                            titulo: 'Teléfono',
                            contenido: _telefonoController.text,
                            editable: true,
                            controller: _telefonoController,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoCard(
                            icon: Icons.location_on_outlined,
                            titulo: 'Dirección',
                            contenido: _direccionController.text,
                            editable: true,
                            controller: _direccionController,
                          ),
                          const SizedBox(height: 12),
                          _buildInfoCard(
                            icon: Icons.work_outline,
                            titulo: 'Rol',
                            contenido: _datosUsuario?['rol'] == 'admin'
                                ? 'Administrador'
                                : 'Trabajador',
                            editable: false,
                          ),

                          if (_editando) ...[
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setState(() {
                                        _editando = false;
                                        _cargarDatosUsuario();
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey.shade700,
                                      side: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _guardarCambios,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TemaApp.verdePrimario,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Guardar cambios'),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // ✅ BOTÓN CERRAR SESIÓN
                          if (!_editando) ...[
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _cerrarSesion,
                                icon: const Icon(Icons.logout),
                                label: const Text('Cerrar sesión'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String titulo,
    required String contenido,
    required bool editable,
    TextEditingController? controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TemaApp.verdeClaro.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: TemaApp.verdePrimario, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                if (_editando && editable && controller != null)
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  )
                else
                  Text(
                    contenido.isEmpty ? 'No especificado' : contenido,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
              ],
            ),
          ),
          if (editable && !_editando)
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Tema visual profesional con colores agrícolas para MoniScan
class TemaApp {
  // Paleta de colores principal (tonos verdes agrícolas)
  static const Color verdePrimario = Color(
    0xFF2E7D32,
  ); // Verde oscuro profesional
  static const Color verdeSecundario = Color(0xFF4CAF50); // Verde medio
  static const Color verdeClaro = Color(0xFF81C784); // Verde claro
  static const Color verdeAcento = Color(0xFF66BB6A);

  // Colores de soporte
  static const Color colorFondo = Color(0xFFF5F5F5);
  static const Color colorTarjeta = Color(0xFFFFFFFF);
  static const Color colorTexto = Color(0xFF212121);
  static const Color colorTextoSecundario = Color(0xFF757575);
  static const Color colorError = Color(0xFFD32F2F);
  static const Color colorExito = Color(0xFF388E3C);
  static const Color colorAdvertencia = Color(0xFFFFA000);
  static const Color colorInfo = Color(0xFF1976D2);

  // Degradados
  static const LinearGradient degradadoVerde = LinearGradient(
    colors: [verdePrimario, verdeSecundario],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Tema claro de la aplicación
  static ThemeData obtenerTemaClaro() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: verdePrimario,
        secondary: verdeSecundario,
        tertiary: verdeAcento,
        surface: colorTarjeta,
        background: colorFondo,
        error: colorError,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: colorTexto,
        onBackground: colorTexto,
        onError: Colors.white,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: verdePrimario,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // Botones elevados
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: verdePrimario,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // Tarjetas
      cardTheme: CardThemeData(
        color: colorTarjeta,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),

      // Campos de texto
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: verdePrimario, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorError, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorError, width: 2),
        ),
        labelStyle: const TextStyle(color: colorTextoSecundario),
        hintStyle: TextStyle(color: Colors.grey[400]),
      ),

      // FloatingActionButton
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: verdePrimario,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // Tipografía
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: colorTexto,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: colorTexto,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: colorTexto,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorTexto,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colorTexto,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: colorTexto),
        bodyMedium: TextStyle(fontSize: 14, color: colorTextoSecundario),
      ),

      // IconTheme
      iconTheme: const IconThemeData(color: verdePrimario, size: 24),
    );
  }

  /// Estilo para botones de opciones principales
  static ButtonStyle estiloBotonOpcion(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
    );
  }

  /// Estilo para contenedores de detección
  static BoxDecoration decoracionDeteccion() {
    return BoxDecoration(
      color: colorTarjeta,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey[300]!),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

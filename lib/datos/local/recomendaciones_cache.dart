// lib/datos/local/recomendaciones_cache.dart
import '../modelos/recomendacion.dart';

class RecomendacionesCache {
  static final RecomendacionesCache _instancia =
      RecomendacionesCache._interno();
  factory RecomendacionesCache() => _instancia;
  RecomendacionesCache._interno();

  List<Recomendacion> obtenerPorFase(String fase) {
    final todasLasRecomendaciones = _obtenerTodasRecomendaciones();
    return todasLasRecomendaciones
        .where((r) => r.fase.toLowerCase() == fase.toLowerCase())
        .toList();
  }

  List<Recomendacion> obtenerTodas() {
    return _obtenerTodasRecomendaciones();
  }

  List<Recomendacion> _obtenerTodasRecomendaciones() {
    return [
      // ==================== SANA ====================
      Recomendacion(
        id: 'rec_sana_1',
        fase: 'SANA',
        titulo: 'Mantener Monitoreo Preventivo',
        descripcion:
            'La mazorca está sana. Continúa con las prácticas preventivas para evitar infecciones futuras.',
        acciones: [
          'Realizar inspecciones semanales de todas las mazorcas',
          'Mantener buena ventilación en el cultivo mediante poda',
          'Eliminar mazorcas enfermas cercanas inmediatamente',
          'Aplicar fungicidas preventivos si el clima es muy húmedo',
          'Registrar la ubicación GPS para seguimiento posterior',
        ],
        prioridad: 3,
        fechaCreacion: DateTime.now(),
      ),

      // ==================== FASE INICIAL ====================
      Recomendacion(
        id: 'rec_inicial_1',
        fase: 'FASE_INICIAL',
        titulo: 'Acción Inmediata Requerida',
        descripcion:
            'Primeros síntomas detectados. La intervención temprana es crucial para evitar propagación.',
        acciones: [
          'Remover y destruir la mazorca afectada INMEDIATAMENTE',
          'Aplicar fungicida cúprico en mazorcas vecinas (radio de 3 metros)',
          'Aumentar frecuencia de inspección a cada 3 días en esta área',
          'Mejorar poda para aumentar ventilación y reducir humedad',
          'Desinfectar herramientas después de manipular mazorcas infectadas',
          'Marcar el área para monitoreo intensivo',
        ],
        prioridad: 1,
        fechaCreacion: DateTime.now(),
      ),

      // ==================== FASE INTERMEDIA ====================
      Recomendacion(
        id: 'rec_intermedia_1',
        fase: 'FASE_INTERMEDIA',
        titulo: 'Control Urgente de Propagación',
        descripcion:
            'La enfermedad está avanzando. Medidas urgentes son necesarias para evitar pérdidas mayores.',
        acciones: [
          'Eliminar TODAS las mazorcas afectadas del árbol',
          'Quemar el material infectado FUERA de la plantación',
          'Aplicar fungicida sistémico en área de 5 metros alrededor',
          'Implementar poda sanitaria agresiva para mejorar circulación de aire',
          'Desinfectar herramientas con solución de cloro al 10% después de cada uso',
          'Inspeccionar diariamente mazorcas vecinas',
          'Considerar tratamiento foliar preventivo en todo el lote',
          'Evitar riego por aspersión (favorece propagación)',
        ],
        prioridad: 1,
        fechaCreacion: DateTime.now(),
      ),

      // ==================== FASE AVANZADA ====================
      Recomendacion(
        id: 'rec_avanzada_1',
        fase: 'FASE_AVANZADA',
        titulo: 'Manejo de Brote Severo - Contención Crítica',
        descripcion:
            'Infección avanzada detectada. Proteger mazorcas sanas es la prioridad absoluta.',
        acciones: [
          'ELIMINAR todas las mazorcas afectadas del árbol URGENTEMENTE',
          'Aplicar fungicida de amplio espectro en toda el área circundante',
          'Implementar barrera química alrededor de la zona infectada (10 metros)',
          'Realizar poda sanitaria intensiva en el árbol afectado',
          'Considerar cosecha temprana de mazorcas sanas cercanas',
          'Quemar todo material vegetal infectado inmediatamente',
          'Establecer zona de cuarentena (no mover herramientas/personas sin desinfección)',
          'Aumentar aplicaciones de fungicida a 2 veces por semana',
          'Evaluar si más del 50% del árbol está afectado para considerar remoción total',
          'Notificar al supervisor técnico para evaluación especializada',
        ],
        prioridad: 1,
        fechaCreacion: DateTime.now(),
      ),
    ];
  }

  List<Map<String, dynamic>> obtenerChecklist(String fase) {
    final recomendaciones = obtenerPorFase(fase);
    if (recomendaciones.isEmpty) return [];

    final acciones = recomendaciones.first.acciones;
    return acciones
        .map(
          (accion) => {
            'accion': accion,
            'completada': false,
            'timestamp': null,
          },
        )
        .toList();
  }
}

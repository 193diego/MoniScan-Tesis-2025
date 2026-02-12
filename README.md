# 🍫🌱 MoniScan – Detección de Moniliasis en Cacao

Aplicativo web y móvil para la detección y seguimiento temprano de moniliasis en cacao CCN-51 mediante visión por computadora.

---

## 🎓 Proyecto de Titulación

**Universidad Agraria del Ecuador**
Facultad de Ciencias Agrarias
Carrera Computación

Trabajo de titulación previo a la obtención del título de:
**Ingeniero en Ciencias de la Computación**

### 👨‍💻 Autores

* Cárdenas Silva Mario Jefrey
* Carvajal Gómez Diego Roberto

### 👨‍🏫 Tutor

Ing. Mario Ibarra Martínez, MSc.

Milagro – Ecuador
2025

---

## 🚀 Tecnologías Utilizadas

* **Flutter** – Aplicativo móvil
* **React** – Aplicativo web administrativo
* **Firebase** – Autenticación y base de datos en la nube
* **YOLOv11 / YOLOv26** – Modelo de visión por computadora
* **Roboflow** – Gestión del dataset
* **Google Colab** – Entrenamiento del modelo

---

## 🧠 Inteligencia Artificial

Se implementó un modelo de detección de objetos basado en YOLO entrenado para identificar:

* Mazorca sana
* Fase inicial de moniliasis
* Fase intermedia
* Fase avanzada

El modelo permite estimar el porcentaje de infección y generar recomendaciones automáticas.

---

## 📱 Aplicativo Móvil (Trabajadores)

* Autenticación con Firebase
* Captura de imágenes
* Procesamiento con modelo YOLO
* Recomendaciones automáticas
* Historial de detecciones
* Seguimiento evolutivo

---

## 💻 Aplicativo Web (Administradora)

* Gestión de trabajadores
* Gestión de tratamientos
* Visualización de detecciones
* Seguimiento de enfermedad
* Reportes y dashboards
* Exportación en PDF y Excel

---

## 🔐 Configuración de Firebase

Por razones de seguridad, los archivos de configuración de Firebase no están incluidos en este repositorio.

Para ejecutar el proyecto:

1. Crear un proyecto en Firebase.
2. Descargar `google-services.json`.
3. Colocarlo en `android/app/`.
4. Configurar Firebase mediante FlutterFire CLI.

---

## 📍 Lugar de Implementación

Finca ubicada en el recinto San Antonio, cantón Naranjito, Guayas – Ecuador.

---

## 📄 Licencia

Proyecto académico con fines investigativos.

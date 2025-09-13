// En lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'sync_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'app_colors.dart'; // Importamos nuestros colores

Future<void> main() async {
  // Asegúrate de que tu función main sea async
  WidgetsFlutterBinding.ensureInitialized();

  // ==========================================================
  // INICIALIZACIÓN DE HIVE - ¡AQUÍ ESTÁ LA CLAVE!
  // ==========================================================
  await Hive.initFlutter();
  // Abre TODAS las cajas que tu app usará en el futuro.
  await Hive.openBox('asistencias_pendientes');
  await Hive.openBox('user_data'); // <-- ESTA LÍNEA ES CRUCIAL
  // ==========================================================

  // Inicialización de Firebase (esto puede ir después de Hive)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  SyncService().startListening();

  // Lógica para decidir qué pantalla mostrar
  final userBox = Hive.box(
    'user_data',
  ); // Esta línea ahora funcionará sin error
  final dni = userBox.get('dni') as String?;
  final nombre = userBox.get('nombre') as String?;
  final area = userBox.get('area') as String?; // <-- CAMBIO: Leemos el área

  runApp(
    MyApp(
      isLoggedIn: dni != null && nombre != null && area != null,
      dni: dni,
      nombre: nombre,
      area: area,
    ),
  );
}

class MyApp extends StatelessWidget {
  // ==========================================================
  // CORRECCIÓN: AÑADIMOS LA DECLARACIÓN DE LOS CAMPOS
  // ==========================================================
  final bool isLoggedIn;
  final String? dni;
  final String? nombre;
  final String? area; // <-- CAMBIO: Añadimos el área
  // ==========================================================

  const MyApp({
    super.key,
    required this.isLoggedIn,
    this.dni,
    this.nombre,
    this.area,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          false, // Opcional: para quitar la cinta de debug
      title: 'App de Asistencia',

      // --- AÑADE O COMPLETA ESTA SECCIÓN ---
      theme: ThemeData(
        // Color principal para elementos como el indicador de carga, etc.
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,

        // Color de fondo para todas las pantallas
        scaffoldBackgroundColor: AppColors.background,

        // Estilo por defecto para las barras de navegación
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.text,
          elevation: 1,
        ),
      ),
      // --- FIN DE LA SECCIÓN ---

      home: isLoggedIn
          ? HomeScreen(dni: dni!, nombre: nombre!, area: area!)
          : const LoginScreen(),
    );
  }
}

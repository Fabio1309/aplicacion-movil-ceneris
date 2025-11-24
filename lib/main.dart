// lib/main.dart

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart'; // Necesario para el calendario en español
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'sync_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'app_colors.dart';
// Importa tu Dashboard si decidiste usarlo como pantalla principal en lugar de HomeScreen
// import 'dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- ¡LÍNEA NUEVA OBLIGATORIA! ---
  // Inicializa los datos de localización para Español.
  // Esto arregla el error "LocaleDataException" en la pantalla de Horas Extra.
  await initializeDateFormatting('es_ES', null);
  // ---------------------------------

  // 1. Inicialización de Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Inicialización de Hive (solo para asistencias offline)
  await Hive.initFlutter();
  await Hive.openBox('asistencias_pendientes');

  // 3. Inicia el servicio de sincronización en segundo plano
  SyncService().startListening();

  // 4. Lógica de sesión con SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final String? dni = prefs.getString('user_dni');
  final String? nombre = prefs.getString('user_nombre');
  final String? area = prefs.getString('user_area');

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
  final bool isLoggedIn;
  final String? dni;
  final String? nombre;
  final String? area;

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
      debugShowCheckedModeBanner: false,
      title: 'Control de Asistencia Ceneris',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.text,
          elevation: 1,
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      // IMPORTANTE: Si ya integraste el DashboardScreen en tu flujo,
      // deberías cambiar 'HomeScreen' por 'DashboardScreen' aquí abajo.
      // Si no, déjalo como está.
      home: isLoggedIn
          ? HomeScreen(dni: dni!, nombre: nombre!, area: area!)
          : const LoginScreen(),
    );
  }
}

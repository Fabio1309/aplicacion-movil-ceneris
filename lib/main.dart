// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Importamos SharedPreferences
import 'firebase_options.dart';
import 'sync_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicialización de Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Inicialización de Hive (solo para asistencias offline)
  await Hive.initFlutter();
  await Hive.openBox('asistencias_pendientes');
  
  // 3. Inicia el servicio de sincronización en segundo plano
  SyncService().startListening();

  // 4. Lógica de sesión con SharedPreferences para decidir la pantalla inicial
  final prefs = await SharedPreferences.getInstance();
  final String? dni = prefs.getString('user_dni');
  final String? nombre = prefs.getString('user_nombre');
  final String? area = prefs.getString('user_area');

  runApp(
    MyApp(
      // La sesión es válida si todos los datos necesarios existen
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
      // Lógica de navegación: si está logueado, va a HomeScreen, sino a LoginScreen
      home: isLoggedIn
          ? HomeScreen(dni: dni!, nombre: nombre!, area: area!)
          : const LoginScreen(),
    );
  }
}
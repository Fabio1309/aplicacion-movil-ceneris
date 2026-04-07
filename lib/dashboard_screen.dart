// lib/dashboard_screen.dart (DISEÑO MEJORADO)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart'; // Asegúrate de tener este archivo o define los colores

// --- IMPORTS DE TUS PANTALLAS ---
import 'login_screen.dart';
import 'home_screen.dart';
import 'solicitud_horas_extra_screen.dart';
import 'justificar_ausencia_screen.dart';
import 'historial_marcaciones_screen.dart';
import 'perfil_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = 'Cargando...';
  String _userArea = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Cargar datos del usuario para la bienvenida
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Obtenemos solo el primer nombre para que no sea tan largo
      final fullName = prefs.getString('user_nombre') ?? 'Usuario';
      _userName = fullName.split(' ')[0];
      _userArea = prefs.getString('user_area') ?? 'General';
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Rescatamos el ID del dispositivo ANTES de borrar todo
    final String? deviceId = prefs.getString('unique_device_id');
    
    // 2. Ahora sí, limpiamos toda la sesión (borramos el token, nombre, dni, etc.)
    await prefs.clear();
    
    // 3. Volvemos a guardar el ID del dispositivo para que sobreviva al cierre de sesión
    if (deviceId != null) {
      await prefs.setString('unique_device_id', deviceId);
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _navigateToAsistencia() async {
    final prefs = await SharedPreferences.getInstance();
    final dni = prefs.getString('user_dni') ?? '';
    final nombre = prefs.getString('user_nombre') ?? 'Usuario';
    final area = prefs.getString('user_area') ?? 'Sin Área';

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            dni: dni,
            nombre: nombre,
            area: area,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Gris muy suave de fondo
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. CABECERA PERSONALIZADA
              // 1. CABECERA PERSONALIZADA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Lado Izquierdo: Foto de Perfil + Textos
                  Row(
                    children: [
                      // El Avatar clickeable
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (context) => const PerfilScreen()),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.primary,
                            // Si a futuro agregas fotos reales a tu base de datos, 
                            // aquí usarías backgroundImage: NetworkImage(url)
                            child: Icon(Icons.person, color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16), // Espacio entre foto y texto
                      
                      // Textos de Bienvenida
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hola, $_userName 👋',
                            style: const TextStyle(
                              fontSize: 22, // Ajustado ligeramente para encajar mejor
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userArea,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Lado Derecho: Botón de Salir con estilo suave
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.logout_rounded,
                          color: Colors.redAccent),
                      tooltip: 'Cerrar Sesión',
                      onPressed: _logout,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              const Text(
                '¿Qué deseas hacer hoy?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),

              const SizedBox(height: 20),

              // 2. GRILLA DE OPCIONES
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.85, // Hace las tarjetas un poco más altas
                  children: <Widget>[
                    // Opción 1: Asistencia
                    DashboardCard(
                      icon: Icons.fingerprint,
                      title: 'Marcar\nAsistencia',
                      colorTheme: Colors.blueAccent,
                      onTap: _navigateToAsistencia,
                    ),

                    // Opción 2: Horas Extra
                    DashboardCard(
                      icon: Icons.access_time_filled_rounded,
                      title: 'Solicitar\nH. Extra',
                      colorTheme: Colors.orangeAccent,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (context) =>
                                  const SolicitudHorasExtraScreen()),
                        );
                      },
                    ),

                    // Opción 3: Justificar Ausencia
                    DashboardCard(
                      icon: Icons.sick_rounded, // Icono más representativo
                      title: 'Justificar\nAusencia',
                      colorTheme: Colors.redAccent,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (context) =>
                                  const JustificarAusenciaScreen()),
                        );
                      },
                    ),

                    // Opción 4: Historial de Marcaciones
                    DashboardCard(
                      icon: Icons.history_edu_rounded, // Icono de historial
                      title: 'Historial\nMarcaciones',
                      colorTheme: Colors.indigoAccent,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (context) =>
                                  HistorialMarcacionesScreen()),
                        );
                      },
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
}

// 3. WIDGET DE TARJETA MEJORADO
class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color colorTheme;

  const DashboardCard({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.colorTheme,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              spreadRadius: 2,
              blurRadius: 15,
              offset: const Offset(0, 5), // Sombra suave hacia abajo
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Círculo de fondo para el icono
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorTheme.withOpacity(0.1), // Fondo suave del color
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 38,
                color: colorTheme, // Color fuerte para el icono
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black87,
                height: 1.2, // Mejor espaciado entre líneas
              ),
            ),
          ],
        ),
      ),
    );
  }
}

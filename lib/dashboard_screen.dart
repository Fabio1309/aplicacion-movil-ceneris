// lib/dashboard_screen.dart (VERSIÓN FINAL Y CORREGIDA)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Importa tus otras pantallas
import 'login_screen.dart';
import 'home_screen.dart'; // Tu pantalla de asistencia
import 'solicitud_horas_extra_screen.dart'; // La pantalla que creamos

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // Función para cerrar sesión, sin cambios.
  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  // --- ¡NUEVA FUNCIÓN! ---
  // Esta función se encarga de leer los datos del usuario guardados
  // y navegar a la pantalla de asistencia.
  Future<void> _navigateToAsistencia(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    // Leemos los datos guardados durante el login
    final dni = prefs.getString('user_dni') ?? '';
    final nombre = prefs.getString('user_nombre') ?? 'Usuario';
    final area = prefs.getString('user_area') ?? 'Sin Área';

    // Verificamos si el widget sigue montado antes de navegar
    if (context.mounted) {
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
      appBar: AppBar(
        title: const Text('CENERIS Asistencia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Cerrar Sesión',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: <Widget>[
            DashboardCard(
              icon: Icons.timer_outlined,
              title: 'Asistencia',
              // --- ¡CAMBIO CLAVE AQUÍ! ---
              // Ahora llamamos a nuestra nueva función asíncrona.
              onTap: () => _navigateToAsistencia(context),
            ),
            DashboardCard(
              icon: Icons.add_alarm_outlined,
              title: 'Solicitar H. Extra',
              onTap: () {
                // Navega a la nueva pantalla de solicitud (sin cambios aquí)
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => const SolicitudHorasExtraScreen()),
                );
              },
            ),
            DashboardCard(
              icon: Icons.edit_calendar_outlined,
              title: 'Justificar Ausencia',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Funcionalidad en desarrollo.')),
                );
              },
            ),
            DashboardCard(
              icon: Icons.more_horiz,
              title: 'Más Opciones',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Funcionalidad en desarrollo.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Widget reutilizable para las tarjetas del dashboard (sin cambios)
class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const DashboardCard({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

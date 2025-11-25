// lib/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- IMPORTS DE TUS PANTALLAS ---
import 'login_screen.dart';
import 'home_screen.dart';
import 'solicitud_horas_extra_screen.dart';
import 'justificar_ausencia_screen.dart'; // <--- ASEGÚRATE DE IMPORTAR LA NUEVA PANTALLA

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // Función para cerrar sesión
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

  // Navegar a la pantalla de marcar asistencia
  Future<void> _navigateToAsistencia(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final dni = prefs.getString('user_dni') ?? '';
    final nombre = prefs.getString('user_nombre') ?? 'Usuario';
    final area = prefs.getString('user_area') ?? 'Sin Área';

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
        backgroundColor: Colors.white, // Opcional: Ajuste estético
        foregroundColor: Colors.black, // Opcional: Ajuste estético
        elevation: 1,
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
            // 1. ASISTENCIA
            DashboardCard(
              icon: Icons.timer_outlined,
              title: 'Marcar Asistencia',
              colorIcon: Colors.blue,
              onTap: () => _navigateToAsistencia(context),
            ),

            // 2. HORAS EXTRA
            DashboardCard(
              icon: Icons.add_alarm_outlined,
              title: 'Solicitar H. Extra',
              colorIcon: Colors.orange,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => const SolicitudHorasExtraScreen()),
                );
              },
            ),

            // 3. JUSTIFICAR AUSENCIA (¡ACTUALIZADO!)
            DashboardCard(
              icon: Icons.edit_calendar_outlined,
              title: 'Justificar Ausencia',
              colorIcon: Colors.redAccent,
              onTap: () {
                // Redirige a la nueva pantalla con Calendario y Panel Dinámico
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => const JustificarAusenciaScreen()),
                );
              },
            ),

            // 4. MÁS OPCIONES
            DashboardCard(
              icon: Icons.more_horiz,
              title: 'Más Opciones',
              colorIcon: Colors.grey,
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

// Widget reutilizable (Le agregué colorIcon para darle más vida)
class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? colorIcon; // Opcional para mejorar diseño

  const DashboardCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.colorIcon,
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
            Icon(icon,
                size: 48, color: colorIcon ?? Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

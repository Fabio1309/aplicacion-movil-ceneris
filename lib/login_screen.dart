// lib/login_screen.dart

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _dniController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _verifyAndProceed() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() { _isLoading = true; });
    final dni = _dniController.text.trim();

    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String? currentDeviceId;
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        currentDeviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        currentDeviceId = iosInfo.identifierForVendor;
      }

      if (currentDeviceId == null) {
        _showError('No se pudo obtener la identificación del dispositivo.');
        return;
      }

      final trabajadorRef = FirebaseFirestore.instance.collection('trabajadores').doc(dni);
      final trabajadorSnap = await trabajadorRef.get();

      if (!trabajadorSnap.exists || !(trabajadorSnap.data()?['activo'] ?? false)) {
        _showError('DNI no encontrado o inactivo. Contacte al administrador.');
        return;
      }

      final deviceRef = FirebaseFirestore.instance.collection('dispositivos').doc(currentDeviceId);
      final deviceSnap = await deviceRef.get();
      
      final trabajadorData = trabajadorSnap.data()!;
      final nombreDelUsuario = trabajadorData['nombre'] ?? 'Usuario Desconocido';
      final areaDelUsuario = trabajadorData['area'] ?? 'Sin Área';

      if (!deviceSnap.exists) {
        // El dispositivo no está registrado. Lo creamos con el nombre del usuario
        // y le damos permiso a este DNI inmediatamente.
        final newDeviceName = 'Dispositivo de $nombreDelUsuario';
        await deviceRef.set({
            'nombreDispositivo': newDeviceName,
            'creadoEn': FieldValue.serverTimestamp(),
            'trabajadoresPermitidos': [dni] // ¡Se auto-asigna!
        });
        print('Dispositivo nuevo registrado como "$newDeviceName" y asignado a $dni');
        // Ahora que está registrado y asignado, procedemos directamente.
        _proceedToHomeScreen(dni, nombreDelUsuario, areaDelUsuario);
        return; // Salimos de la función aquí porque ya hemos navegado
      }

      // Si el dispositivo ya existe, verificamos el permiso
      final data = deviceSnap.data()!;
      final List<dynamic> trabajadoresPermitidos = data['trabajadoresPermitidos'] ?? [];

      if (trabajadoresPermitidos.contains(dni)) {
        _proceedToHomeScreen(dni, nombreDelUsuario, areaDelUsuario);
      } else {
        _showError('No tienes permiso para marcar en este dispositivo.');
      }
      
    } catch (e) {
      _showError('Error de red al verificar. Intente de nuevo.');
      print("Error en login: $e");
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  void _proceedToHomeScreen(String dni, String nombre, String area) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_dni', dni);
    await prefs.setString('user_nombre', nombre);
    await prefs.setString('user_area', area);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(dni: dni, nombre: nombre, area: area),
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/images/image.png', height: 80),
                  const SizedBox(height: 24),
                  const Text(
                    'Identificación de Empleado',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Por favor, ingrese su DNI para continuar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: AppColors.textLight),
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _dniController,
                    decoration: InputDecoration(
                      labelText: 'DNI',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.badge_outlined),
                      hintText: 'Ingrese su número de DNI',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El DNI es obligatorio';
                      }
                      if (value.length < 8) {
                        return 'El DNI debe tener 8 dígitos';
                      }
                      return null;
                    }
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary))
                      : ElevatedButton(
                          onPressed: _verifyAndProceed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          child: const Text('Verificar y Continuar'),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// lib/login_screen.dart

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
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

    setState(() {
      _isLoading = true;
    });
    final dni = _dniController.text.trim();

    try {
      // 1. Obtener el ID del dispositivo actual
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String? currentDeviceId;
      if (Theme.of(context).platform == TargetPlatform.android) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        currentDeviceId = androidInfo.id;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        currentDeviceId = iosInfo.identifierForVendor;
      }

      if (currentDeviceId == null) {
        _showError('No se pudo obtener el ID del dispositivo.');
        return;
      }

      // 2. Verificar el DNI en Firestore
      final docRef =
          FirebaseFirestore.instance.collection('trabajadores').doc(dni);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data()!;
        final String nombreFromDB = data['nombre'] ?? 'Nombre no encontrado';
        final String areaFromDB = data['area'] ?? 'Sin Área';
        final deviceIdVinculado = data['deviceIdVinculado'];

        // ==========================================================
        // INICIO DE LA NUEVA LÓGICA DE SEGURIDAD BIDIRECCIONAL
        // ==========================================================

        if (deviceIdVinculado == null || deviceIdVinculado == '') {
          // CASO A: El trabajador no tiene dispositivo vinculado.
          // ANTES de vincular, verificamos si este dispositivo ya está en uso.

          final deviceQuery = await FirebaseFirestore.instance
              .collection('trabajadores')
              .where('deviceIdVinculado', isEqualTo: currentDeviceId)
              .limit(1)
              .get();

          if (deviceQuery.docs.isNotEmpty) {
            // ¡Fraude! Este dispositivo ya está vinculado a otro DNI.
            _showError(
                'Este dispositivo ya está en uso por otro trabajador. Contacte al administrador.');
          } else {
            // El dispositivo está libre. Procedemos a vincularlo.
            await docRef.update({'deviceIdVinculado': currentDeviceId});
            _proceedToHomeScreen(dni, nombreFromDB, areaFromDB);
          }
        } else if (deviceIdVinculado == currentDeviceId) {
          // CASO B: El trabajador ya está vinculado y es el dispositivo correcto.
          _proceedToHomeScreen(dni, nombreFromDB, areaFromDB);
        } else {
          // CASO C: El DNI está vinculado a OTRO dispositivo.
          _showError('Este DNI ya está vinculado a otro dispositivo.');
        }
        // ==========================================================
        // FIN DE LA NUEVA LÓGICA DE SEGURIDAD
        // ==========================================================
      } else {
        _showError('DNI no autorizado. Contacte al administrador.');
      }
    } catch (e) {
      _showError('Error de red al verificar. Intente de nuevo.');
      print("Error en login: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _proceedToHomeScreen(String dni, String nombre, String area) async {
    final userBox = Hive.box('user_data');
    await userBox.put('dni', dni);
    await userBox.put('nombre', nombre);
    await userBox.put('area', area);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) =>
              HomeScreen(dni: dni, nombre: nombre, area: area),
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
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
                    decoration: const InputDecoration(
                      labelText: 'DNI',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.badge),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'El DNI es obligatorio'
                            : null,
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

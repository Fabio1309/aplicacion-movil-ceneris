// lib/login_screen.dart (VERSIÓN FINAL CON VALIDACIÓN DE DISPOSITIVO EN EL LOGIN)

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dashboard_screen.dart';
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
  String? _deviceId; // CORRECCIÓN: Se declara la variable para guardar el ID

  final String _apiUrl = 'https://ceneris-web-oror.onrender.com/api';

  @override
  void initState() {
    super.initState();
    _getDeviceId();
  }

  Future<void> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        _deviceId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        _deviceId = (await deviceInfo.iosInfo).identifierForVendor;
      }
      print("[DEVICE INFO] ID obtenido: $_deviceId");
    } catch (e) {
      print("Error al obtener el ID del dispositivo: $e");
      if (mounted)
        _showError(
            "No se pudo obtener el ID del dispositivo. La app no puede continuar.");
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_deviceId == null) {
      _showError("El ID del dispositivo no está disponible. Reinicie la app.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final dni = _dniController.text.trim();
    final password = dni;

    try {
      final Uri loginUri = Uri.parse('$_apiUrl/token/');

      final requestBody = json.encode({
        'username': dni,
        'password': password,
        'device_id': _deviceId,
      });

      print("[LOGIN] Enviando: $requestBody");

      // CORRECCIÓN: Se eliminó la llamada a http.post duplicada.
      final response = await http
          .post(
            loginUri,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = json.decode(utf8.decode(response.bodyBytes));
        final token = responseData['access'];
        final userData = responseData['user'];

        if (token == null || userData == null) {
          _showError('Respuesta inválida del servidor.');
          return;
        }

        final nombreUsuario = userData['nombre'] ?? 'Usuario';
        final areaUsuario = userData['area'] ?? 'Sin Área';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('authToken', token);
        await prefs.setString('user_dni', dni);
        await prefs.setString('user_nombre', nombreUsuario);
        await prefs.setString('user_area', areaUsuario);

        _proceedToDashboard();
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        final errorMessage = errorData['detail'] ??
            errorData['non_field_errors']?[0] ??
            'Credenciales o permisos incorrectos.';
        _showError(errorMessage);
      }
    } catch (e) {
      _showError('Error de red al conectar con el servidor.');
      print("Error en login: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _proceedToDashboard() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const DashboardScreen(),
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
    // El widget build no necesita cambios
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                // ... (El contenido de la columna se mantiene igual) ...
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/images/image.png', height: 80),
                  const SizedBox(height: 24),
                  const Text('Identificación de Empleado',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  const SizedBox(height: 16),
                  const Text('Por favor, ingrese su DNI para continuar.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 16, color: AppColors.textLight)),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _dniController,
                    decoration: const InputDecoration(
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
                    },
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary))
                      : ElevatedButton(
                          onPressed: _login,
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

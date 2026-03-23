// lib/login_screen.dart (DISEÑO MEJORADO)

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:uuid/uuid.dart';
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
  String? _deviceId;
  bool _isObscure =
      true; // Para ocultar/mostrar contraseña si quisieras usarla a futuro

  final String _apiUrl = 'https://ceneris-web-oror.onrender.com/api';

  @override
  void initState() {
    super.initState();
    _initializeDeviceId();
  }

  // --- LOGICA DE DISPOSITIVO (INTACTA) ---
  Future<void> _initializeDeviceId() async {
    try {
      _deviceId = await getUniqueDeviceId();
    } catch (e) {
      print("Error al obtener el ID único del dispositivo: $e");
      if (mounted) _showError("No se pudo generar un ID para el dispositivo.");
    }
  }

  Future<String> getUniqueDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('unique_device_id');
    if (deviceId == null) {
      try {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final info = await deviceInfo.androidInfo;
          deviceId = info.id;
        } else if (Platform.isIOS) {
          final info = await deviceInfo.iosInfo;
          deviceId = info.identifierForVendor;
        }
      } catch (e) {
        print('[DEVICE INFO] error leyendo device info: $e');
      }
      deviceId ??= const Uuid().v4();
      await prefs.setString('unique_device_id', deviceId);
    }
    return deviceId;
  }

  // --- LOGICA DE LOGIN (INTACTA CON MEJORA DE ERROR) ---
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_deviceId == null) {
      _showError("El ID del dispositivo no está disponible. Reinicie la app.");
      return;
    }

    setState(() => _isLoading = true);

    final dni = _dniController.text.trim();
    // Asumimos que la contraseña es el mismo DNI por defecto
    final password = dni;

    try {
      final Uri loginUri = Uri.parse('$_apiUrl/token/');
      final requestBody = json.encode({
        'username': dni,
        'password': password,
        'device_id': _deviceId,
      });

      print("[LOGIN] Enviando: $requestBody");

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
        print("❌ Error del servidor: ${response.statusCode}");
        print("❌ Cuerpo de respuesta: ${response.body}");

        try {
          final errorData = json.decode(utf8.decode(response.bodyBytes));
          final errorMessage = errorData['detail'] ??
              errorData['non_field_errors']?[0] ??
              'Credenciales incorrectas.';
          _showError(errorMessage);
        } catch (e) {
          _showError('Error del servidor (${response.statusCode}).');
        }
      }
    } catch (e) {
      _showError('Error de conexión. Verifique su internet.');
      print("Error en login: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _proceedToDashboard() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // --- NUEVO DISEÑO VISUAL ---
  @override
  Widget build(BuildContext context) {
    // Obtenemos el tamaño de la pantalla
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white, // Fondo base
      body: SingleChildScrollView(
        child: SizedBox(
          height: size.height,
          child: Stack(
            children: [
              // 1. Fondo Superior con Degradado Curvo
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: size.height * 0.45,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // AQUÍ CAMBIAS LA IMAGEN
                      // Asegúrate de que la ruta 'assets/images/logo_login.png' exista
                      // Si no tienes imagen aún, usa un Icono grande temporalmente:
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        // Cambia esto por Image.asset('assets/images/logo_login.png', height: 100)
                        child: Image.asset(
                          'assets/images/image.png',
                          height: 100,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        'CENERIS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Tarjeta del Formulario (Flotante)
              Positioned(
                top: size.height * 0.38, // Ajusta para que solape el fondo
                left: 20,
                right: 20,
                child: Card(
                  elevation: 8,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Bienvenido',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ingrese sus credenciales para acceder',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // Input DNI Estilizado
                          TextFormField(
                            controller: _dniController,
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'DNI / Usuario',
                              prefixIcon: const Icon(Icons.person_outline,
                                  color: AppColors.primary),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 1.5),
                              ),
                              counterText: "", // Oculta el contador pequeño
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty)
                                return 'Ingrese su DNI';
                              if (value.length < 8)
                                return 'DNI inválido (mín. 8 dígitos)';
                              return null;
                            },
                          ),

                          const SizedBox(height: 30),

                          // Botón de Login
                          _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary))
                              : Container(
                                  height: 55,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            AppColors.primary.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation:
                                          0, // Quitamos elevación predeterminada para usar la sombra custom
                                    ),
                                    child: const Text(
                                      'INICIAR SESIÓN',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Texto inferior (Footer)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Text(
                  'Versión 1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

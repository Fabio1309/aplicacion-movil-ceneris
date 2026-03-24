// lib/login_screen.dart (DISEÑO MEJORADO CON CAMPO DE CONTRASEÑA)

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
  // NUEVO: Controlador para capturar lo que se escribe en la contraseña
  final _passwordController = TextEditingController(); 
  
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _deviceId;
  // NUEVO: Estado para ocultar/mostrar la contraseña
  bool _isObscure = true; 

  final String _apiUrl = 'https://ceneris-web-oror.onrender.com/api';

  @override
  void initState() {
    super.initState();
    _initializeDeviceId();
  }

  @override
  void dispose() {
    // Buena práctica: limpiar los controladores al cerrar la pantalla
    _dniController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    
    // Si la app se instala por primera vez, no hay ID guardado
    if (deviceId == null) {
      // Inventamos un código único en el mundo (ej. 550e8400-e29b-41d4-a716-446655440000)
      deviceId = const Uuid().v4(); 
      // Lo guardamos bajo llave. Nunca cambiará a menos que desinstalen la app.
      await prefs.setString('unique_device_id', deviceId);
    }
    
    return deviceId;
  }

  // --- LOGICA DE LOGIN ---
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_deviceId == null) {
      _showError("El ID del dispositivo no está disponible. Reinicie la app.");
      return;
    }

    setState(() => _isLoading = true);

    final dni = _dniController.text.trim();
    // NUEVO: Ahora tomamos la contraseña real que escribió el usuario
    final password = _passwordController.text.trim();

    try {
      final Uri loginUri = Uri.parse('$_apiUrl/token/');
      final requestBody = json.encode({
        'username': dni,
        'password': password,
        'device_id': _deviceId,
      });

      // ==========================================================
      // BLOQUE DE DEPURACIÓN
      // ==========================================================
      print('\n======================================================');
      print('🚀 INICIANDO INTENTO DE LOGIN');
      print('🌐 URL a la que se apunta: $loginUri');
      print('👤 Usuario (DNI): "$dni"');
      print('🔑 Contraseña real enviada: "$password"');
      print('📱 Device ID capturado: "$_deviceId"');
      print('======================================================\n');
      // ==========================================================

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
        final usuarioSistema = userData['usuario'] ?? ''; // NUEVO
        final dniReal = userData['dni'] ?? '';
        final emailReal = userData['email'] ?? 'No registrado';
        final telefonoReal = userData['telefono'] ?? 'No registrado';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('authToken', token);
        await prefs.setString('user_nombre', nombreUsuario);
        await prefs.setString('user_area', areaUsuario);
        await prefs.setString('user_username', usuarioSistema);
        await prefs.setString('user_dni', dniReal);
        await prefs.setString('user_email', emailReal);
        await prefs.setString('user_telefono', telefonoReal);

        _proceedToDashboard();
      } else {
        print("\n❌ --- ERROR DE AUTENTICACIÓN --- ❌");
        print("Código de estado: ${response.statusCode}");
        print("Respuesta del servidor: ${response.body}");
        print("------------------------------------\n");

        try {
          final errorData = json.decode(utf8.decode(response.bodyBytes));
          String errorMessage = 'Credenciales incorrectas.';

          // 1. Revisamos si viene el campo "detail"
          if (errorData['detail'] != null) {
            if (errorData['detail'] is List) {
              errorMessage = errorData['detail'][0]; // Extraemos el texto de la lista
            } else {
              errorMessage = errorData['detail'].toString(); // Lo tomamos como texto directo
            }
          } 
          // 2. Si no viene "detail", revisamos si viene "non_field_errors"
          else if (errorData['non_field_errors'] != null && errorData['non_field_errors'] is List) {
            errorMessage = errorData['non_field_errors'][0];
          }

          // 3. Mostramos el mensaje exacto en la pantalla
          _showError(errorMessage);
          
        } catch (e) {
          // Si el servidor manda un HTML o algo que no es JSON
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: SizedBox(
          height: size.height,
          child: Stack(
            children: [
              // 1. Fondo Superior
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
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
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

              // 2. Tarjeta del Formulario
              Positioned(
                top: size.height * 0.38,
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

                          // --- INPUT DNI ---
                          TextFormField(
                            controller: _dniController,
                            keyboardType: TextInputType.text,
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
                              counterText: "",
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingrese su usuario';
                              }
                              if (value.trim().length < 3) {
                                return 'Usuario inválido (mín. 3 caracteres)';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // --- NUEVO INPUT: CONTRASEÑA ---
                          TextFormField(
                            controller: _passwordController,
                            // obscureText oculta los caracteres si está en true
                            obscureText: _isObscure, 
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline,
                                  color: AppColors.primary),
                              // Botón de ojito para mostrar/ocultar contraseña
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isObscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isObscure = !_isObscure;
                                  });
                                },
                              ),
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
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingrese su contraseña';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 30),

                          // --- BOTÓN DE LOGIN ---
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
                                      elevation: 0,
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

              // 3. Texto inferior
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
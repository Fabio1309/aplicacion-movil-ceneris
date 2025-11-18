// lib/login_screen.dart (VERSIÓN MEJORADA - SIN FIREBASE)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_screen.dart'; // Asegúrate que la ruta sea correcta
import 'app_colors.dart'; // Asegúrate que la ruta sea correcta

// CAMBIO: Se elimina la dependencia de Firebase
// import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _dniController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isProbing = false;

  // CAMBIO: ¡IMPORTANTE! Actualiza esta URL a la de tu servidor en Render.
  // La URL local se deja como ejemplo para cuando desarrolles en tu máquina.
  // final String _apiUrl = 'http://10.0.2.2:8000/api'; // Para emulador Android
  final String _apiUrl = 'https://ceneris-web-oror.onrender.com/api';

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final dni = _dniController.text.trim();
    final password = dni; // La contraseña por defecto es el mismo DNI

    try {
      // --- PASO 1: Autenticarse contra la API de Django ---
      final Uri loginUri = Uri.parse('$_apiUrl/token/');
      final String requestBody = json.encode({
        'username': dni,
        'password': password,
      });

      // Prints de depuración: URL, headers y body
      print('[LOGIN] POST $loginUri');
      print('[LOGIN] headers=${{'Content-Type': 'application/json'}}');
      print('[LOGIN] body=$requestBody');

      final response = await http
          .post(
            loginUri,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 20));

      // Imprimir respuesta cruda para depuración
      print('[LOGIN] status=${response.statusCode}');
      print('[LOGIN] body=${utf8.decode(response.bodyBytes)}');

      if (response.statusCode == 200) {
        // --- PASO 2: Procesar la respuesta del servidor ---
        // Usamos utf8.decode para manejar correctamente caracteres especiales como tildes.
        final responseData = json.decode(utf8.decode(response.bodyBytes));

        final token = responseData['token'];

        // CAMBIO: Obtenemos los datos del usuario directamente de la respuesta de la API.
        final userData = responseData['user'];
        final nombreUsuario = userData['nombre'] ?? 'Usuario';
        final areaUsuario = userData['area'] ?? 'Sin Área';

        if (token == null || userData == null) {
          _showError('Respuesta inválida del servidor.');
          return;
        }

        // --- PASO 3: Guardar los datos en el dispositivo ---
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('authToken', token);
        await prefs.setString('user_dni', dni);
        await prefs.setString('user_nombre', nombreUsuario);
        await prefs.setString('user_area', areaUsuario);

        print('[DEBUG LOGIN] Login exitoso para $nombreUsuario');

        // --- PASO 4: Navegar al Dashboard ---
        _proceedToDashboard();
      } else if (response.statusCode == 404) {
        // Endpoint de login no encontrado en el servidor
        final body = utf8.decode(response.bodyBytes);
        _showError(
            'Endpoint de login no encontrado (404). Pruebe "Probar endpoints".');
        print('[LOGIN] 404 body=$body');
      } else if (response.statusCode == 401) {
        _showError('Credenciales inválidas (401). Revise DNI/contraseña.');
      } else {
        // Otros códigos: mostrar mensaje más informativo
        final body = utf8.decode(response.bodyBytes);
        _showError('Error del servidor: ${response.statusCode}');
        print('[LOGIN] error body=$body');
      }
    } catch (e) {
      // Error de red, timeout, etc.
      _showError('Error de red al conectar con el servidor. Intente de nuevo.');
      print("Error en login: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _allowedLocations = List<Map<String, dynamic>>.from(locationsData);
        });
      }
    }
  }

  // Probador automático de endpoints de login.
  // Intenta una lista de rutas comunes y muestra en consola el resultado.
  Future<void> _probeLoginEndpoints() async {
    if (_isProbing) return;
    setState(() => _isProbing = true);

    final candidatePaths = [
      '/token/',
      '/token/obtain/',
      '/api/token/',
      '/api/token/obtain/',
      '/api-token-auth/',
      '/auth/login/',
      '/api/auth/login/',
      '/login/',
      '/api/login/',
    ];

    final sampleDni = _dniController.text.trim().isNotEmpty
        ? _dniController.text.trim()
        : '72189714';

    for (final path in candidatePaths) {
      final Uri uri = Uri.parse('$_apiUrl${path}');
      final bodyVariants = [
        json.encode({'username': sampleDni, 'password': sampleDni}),
        json.encode({'dni': sampleDni}),
        json.encode({'username': sampleDni}),
      ];

      for (final body in bodyVariants) {
        try {
          print('[PROBE] POST $uri');
          print('[PROBE] body=$body');
          final resp = await http
              .post(uri,
                  headers: {'Content-Type': 'application/json'}, body: body)
              .timeout(const Duration(seconds: 8));

          final respBody = utf8.decode(resp.bodyBytes);
          print('[PROBE] status=${resp.statusCode} body=$respBody');

          if (resp.statusCode == 200 || resp.statusCode == 201) {
            // Intentar detectar token en la respuesta
            try {
              final decoded = json.decode(respBody);
              if (decoded is Map &&
                  (decoded.containsKey('token') ||
                      decoded.containsKey('access') ||
                      decoded.containsKey('user'))) {
                final successMsg = 'Endpoint válido: $uri';
                print('[PROBE] $successMsg');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(successMsg)),
                  );
                }
                setState(() => _isProbing = false);
                return;
              }
            } catch (_) {
              // no JSON
            }
          }
        } catch (e) {
          print('[PROBE] error al probar $uri -> $e');
        }
      }
      // Además intentar GET y OPTIONS para descubrir rutas browsables o info
      try {
        print('[PROBE] GET $uri');
        final getResp = await http.get(uri, headers: {
          'Content-Type': 'application/json'
        }).timeout(const Duration(seconds: 6));
        final getBody = utf8.decode(getResp.bodyBytes);
        print('[PROBE] GET status=${getResp.statusCode} body=$getBody');
        if (getResp.statusCode == 200 || getResp.statusCode == 401) {
          final successMsg =
              'Endpoint accesible (GET): $uri (status=${getResp.statusCode})';
          print('[PROBE] $successMsg');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(successMsg)),
            );
          }
          setState(() => _isProbing = false);
          return;
        }
      } catch (e) {
        print('[PROBE] GET error $uri -> $e');
      }

      try {
        print('[PROBE] OPTIONS $uri');
        final client = http.Client();
        try {
          final req = http.Request('OPTIONS', uri);
          final streamed =
              await client.send(req).timeout(const Duration(seconds: 6));
          final status = streamed.statusCode;
          print('[PROBE] OPTIONS status=$status for $uri');
          if (status == 200) {
            final successMsg = 'Endpoint acepta OPTIONS: $uri';
            print('[PROBE] $successMsg');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(successMsg)),
              );
            }
            setState(() => _isProbing = false);
            return;
          }
        } finally {
          client.close();
        }
      } catch (e) {
        print('[PROBE] OPTIONS error $uri -> $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró endpoint válido.')),
      );
    }
    setState(() => _isProbing = false);
  }

  void _proceedToDashboard() {
    if (mounted) {
      // Usamos pushReplacement para que el usuario no pueda volver atrás al login
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
    // El widget build no necesita cambios, es idéntico al que tenías.
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
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _isProbing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : OutlinedButton.icon(
                              onPressed: _probeLoginEndpoints,
                              icon: const Icon(Icons.search),
                              label: const Text('Probar endpoints')),
                    ],
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

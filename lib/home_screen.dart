// lib/home_screen.dart (VERSIÓN FINAL COMPLETAMENTE MIGRADAD A DJANGO)

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:assistenciaceneris_app/login_screen.dart'; // Ajusta la ruta si es necesario
import 'app_colors.dart';
import 'package:geodesy/geodesy.dart';
import 'dart:io' show SocketException;
import 'dart:async' show TimeoutException;
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HomeScreen extends StatefulWidget {
  final String dni;
  final String nombre;
  final String area;

  const HomeScreen({
    super.key,
    required this.dni,
    required this.nombre,
    required this.area,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _statusMessage = 'Cargando datos del servidor...';
  bool _isLoading = true;
  String? _deviceId;
  List<Map<String, dynamic>> _allowedLocations = [];
  String _lastMarkingType = 'Salida';

  final String _apiUrl = 'https://ceneris-web-oror.onrender.com/api';

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _getDeviceId();
    await _fetchInitialDataFromBackend();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        _deviceId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        _deviceId = (await deviceInfo.iosInfo).identifierForVendor;
      }
    } catch (e) {
      print("Error al obtener el ID del dispositivo: $e");
    }
  }

  Future<void> _fetchInitialDataFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    if (token == null) {
      _showErrorAndLogout(
          'Sesión inválida. Por favor, inicie sesión de nuevo.');
      return;
    }

    try {
      final Uri estadoUri = Uri.parse('$_apiUrl/trabajador/estado/');
      final response = await http.get(
        estadoUri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final newLastMarkingType = data['ultimoTipoMarcacion'] ?? 'Salida';
        final locationsData = data['ubicacionesPermitidas'] as List;

        final newStatusMessage = newLastMarkingType == 'Entrada'
            ? '✅ DENTRO. Marca tu salida.'
            : 'Bienvenido. Marca tu entrada.';

        if (mounted) {
          setState(() {
            _lastMarkingType = newLastMarkingType;
            _statusMessage = newStatusMessage;
            _allowedLocations = List<Map<String, dynamic>>.from(locationsData);
          });
        }
      } else {
        if (mounted)
          setState(
              () => _statusMessage = 'Error al cargar datos del servidor.');
      }
    } catch (e) {
      print("Error de red al obtener datos iniciales: $e");
      if (mounted)
        setState(() => _statusMessage = 'Error de red. Intente más tarde.');
    }
  }

  Future<void> _markAttendance(String markingType) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Iniciando verificación...';
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet =
          connectivityResult.contains(ConnectivityResult.mobile) ||
              connectivityResult.contains(ConnectivityResult.wifi);

      final hasLocationAccess = await _ensureLocationPermissionAndService();
      if (!hasLocationAccess) return;

      if (mounted) setState(() => _statusMessage = 'Obteniendo ubicación...');
      Position currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      if (currentPosition.isMocked) {
        if (mounted)
          setState(() => _statusMessage = '❌ Ubicación simulada detectada.');
        return;
      }

      if (mounted)
        setState(() => _statusMessage = 'Validando área de trabajo...');
      bool isWithinAllowedLocation = false;
      String locationName = "Ubicación desconocida";

      if (!hasInternet) {
        isWithinAllowedLocation = true;
        locationName = "Ubicación no verificada (sin conexión)";
      } else {
        final LatLng userLocation =
            LatLng(currentPosition.latitude, currentPosition.longitude);
        final Geodesy geodesy = Geodesy();
        for (var location in _allowedLocations) {
          if (location['limites'] != null &&
              (location['limites'] as List).isNotEmpty) {
            final List<LatLng> polygonPoints = (location['limites'] as List)
                .map<LatLng>((p) => LatLng(
                    (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
                .toList();
            if (polygonPoints.length >= 3 &&
                geodesy.isGeoPointInPolygon(userLocation, polygonPoints)) {
              isWithinAllowedLocation = true;
              locationName = location['nombre'];
              break;
            }
          } else if (location['latitud'] != null &&
              location['longitud'] != null) {
            final double distance = Geolocator.distanceBetween(
                (location['latitud'] as num).toDouble(),
                (location['longitud'] as num).toDouble(),
                currentPosition.latitude,
                currentPosition.longitude);
            if (distance <= (location['radio'] as num? ?? 30.0).toDouble()) {
              isWithinAllowedLocation = true;
              locationName = location['nombre'];
              break;
            }
          }
        }
      }

      if (isWithinAllowedLocation) {
        // =================== BLOQUE CORREGIDO ===================
        final Map<String, dynamic> attendanceData = {
          'tipo_marcacion': markingType,
          'latitud': currentPosition.latitude,
          'longitud': currentPosition.longitude,
          'device_id': _deviceId,
          'nombre_ubicacion': locationName,
          'timestamp':
              DateTime.now().toIso8601String(), // Corregido el error de tipeo
        };
        // ========================================================
        print('[DEBUG] Enviando al backend: ${json.encode(attendanceData)}');

        if (hasInternet) {
          await _postAttendanceToBackend(attendanceData);
        } else {
          await Hive.box('asistencias_pendientes').add(attendanceData);
          if (mounted) {
            setState(() {
              _lastMarkingType = markingType;
              _statusMessage = '✅ Marcación guardada localmente.';
            });
          }
        }
      } else {
        if (mounted)
          setState(() => _statusMessage = '❌ Estás fuera del área de trabajo.');
      }
    } on SocketException {
      // Este error es específico de problemas de red (sin internet, servidor no encontrado)
      if (mounted)
        setState(() =>
            _statusMessage = '❌ Error de conexión. Verifique su internet.');
      print("Error en _markAttendance: SocketException - Problema de red.");
    } on TimeoutException {
      // Este error ocurre si el servidor no responde a tiempo
      if (mounted)
        setState(() =>
            _statusMessage = '❌ El servidor no responde. Intente más tarde.');
      print(
          "Error en _markAttendance: TimeoutException - El servidor tardó mucho en responder.");
    } catch (e) {
      // Este es el 'catch' general para cualquier otro error
      if (mounted)
        setState(() => _statusMessage = '❌ Ocurrió un error inesperado.');
      print("Error inesperado en _markAttendance: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _postAttendanceToBackend(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/asistencias/registrar/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        final markingType = data['tipo_marcacion'];
        if (mounted) {
          setState(() {
            _lastMarkingType = markingType;
            _statusMessage = markingType == 'Entrada'
                ? '✅ ENTRADA REGISTRADA. ¡Buen trabajo!'
                : '✅ SALIDA REGISTRADA. ¡Hasta pronto!';
          });
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        final errorMessage = errorData['detail'] ??
            errorData['error']?.toString() ??
            'Error del servidor.';
        if (mounted) setState(() => _statusMessage = '❌ ERROR: $errorMessage');
      }
    } catch (e) {
      if (mounted)
        setState(() => _statusMessage = '❌ Error de red al registrar.');
      print("Error de red en post: $e");
    }
  }

  Future<bool> _ensureLocationPermissionAndService() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted)
        setState(() => _statusMessage = '❌ Servicio de ubicación desactivado.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted)
          setState(() => _statusMessage = '❌ Permiso de ubicación denegado.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted)
        setState(() => _statusMessage =
            '❌ Permiso de ubicación denegado permanentemente.');
      return false;
    }
    return true;
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _showErrorAndLogout(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
      );
      _logout();
    }
  }

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cerrar Sesión'),
          content: const Text('¿Estás seguro de que quieres salir?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Salir'),
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // El widget build no necesita cambios
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Bienvenido, ${widget.nombre.split(' ')[0]}'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Cerrar Sesión',
            onPressed: _showLogoutConfirmationDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/images/image.png', height: 80),
                const SizedBox(height: 24),
                const Text('Control de Asistencia',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text('ESTADO ACTUAL',
                          style: TextStyle(
                              color: AppColors.textLight,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 16),
                      Text(_statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.login),
                              label: const Text('ENTRADA'),
                              onPressed:
                                  _isLoading || _lastMarkingType == 'Entrada'
                                      ? null
                                      : () => _markAttendance('Entrada'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade400,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.logout),
                              label: const Text('SALIDA'),
                              onPressed:
                                  _isLoading || _lastMarkingType == 'Salida'
                                      ? null
                                      : () => _markAttendance('Salida'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade400,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                textStyle: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

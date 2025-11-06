// lib/home_screen.dart

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:assistenciaceneris_app/login_screen.dart'; // Ajusta la ruta si es necesario
import 'app_colors.dart';
import 'package:geodesy/geodesy.dart';
import 'package:hive/hive.dart';
import 'package:flutter_security_checker/flutter_security_checker.dart';
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
  String _statusMessage = 'Cargando...';
  bool _isLoading = true;
  String? _deviceId;
  List<Map<String, dynamic>> _allowedLocations = [];
  String _lastMarkingType = 'Salida';

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _getDeviceId();
    await _loadAllowedLocations();
    await _fetchLastMarkingState();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      }
    } catch (e) {
      print("Error al obtener el ID del dispositivo: $e");
    }
  }

  Future<void> _loadAllowedLocations() async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance.collection('ubicaciones').get();
      final locations = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      if (mounted) {
        setState(() {
          _allowedLocations = locations;
        });
      }
    } catch (e) {
      print("Error al cargar ubicaciones: $e");
    }
  }

  Future<void> _fetchLastMarkingState() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final querySnapshot = await FirebaseFirestore.instance
        .collection('asistencias')
        .where('userDni', isEqualTo: widget.dni)
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

      String newStatusMessage;
      String newLastMarkingType = 'Salida';
      if (querySnapshot.docs.isNotEmpty) {
        final lastMarking = querySnapshot.docs.first.data();
        newLastMarkingType = lastMarking['tipoMarcacion'] ?? 'Salida';
      }
      newStatusMessage = newLastMarkingType == 'Entrada'
          ? '✅ DENTRO. Marca tu salida.'
          : 'Bienvenido. Marca tu entrada.';
      if(mounted){
        setState(() {
          _lastMarkingType = newLastMarkingType;
          _statusMessage = newStatusMessage;
        });
      }
    } catch (e) {
      print("Error al obtener el último estado: $e");
      if(mounted){
        setState(() => _statusMessage = 'Error al verificar estado.');
      }
    }
  }

  Future<void> _markAttendance(String markingType) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Iniciando verificación...';
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult.contains(ConnectivityResult.mobile) || connectivityResult.contains(ConnectivityResult.wifi);
      List<dynamic> ubicacionesPermitidasDelTrabajador = [];

      if (hasInternet) {
        final querySnap = await FirebaseFirestore.instance
            .collection('trabajadores')
            .where('dni', isEqualTo: widget.dni) // Busca el documento donde el campo 'dni' coincida.
            .limit(1) // Solo nos interesa el primer resultado.
            .get();

        // Verificamos si la consulta devolvió algún documento.
        if (querySnap.docs.isEmpty) {
          if(mounted) setState(() { _statusMessage = '❌ ERROR: Trabajador no encontrado o inactivo.'; });
          return;
        }

        // Si encontramos un documento, trabajamos con él.
        final trabajadorDoc = querySnap.docs.first;
        if (!(trabajadorDoc.data()['activo'] ?? false)) {
          if(mounted) setState(() { _statusMessage = '❌ ERROR: Trabajador está inactivo.'; });
          return;
        }

        final deviceDoc = await FirebaseFirestore.instance.collection('dispositivos').doc(_deviceId).get();
        if (!deviceDoc.exists) {
            final newDeviceName = 'Dispositivo de ${widget.nombre}';
            await FirebaseFirestore.instance.collection('dispositivos').doc(_deviceId).set({
                'nombreDispositivo': newDeviceName,
                'creadoEn': FieldValue.serverTimestamp(),
                'trabajadoresPermitidos': [widget.dni]
            });
            print('Dispositivo nuevo registrado como "$newDeviceName" y asignado a ${widget.dni}');
        } else {
            final trabajadoresPermitidos = deviceDoc.data()?['trabajadoresPermitidos'] as List<dynamic>? ?? [];
            if (!trabajadoresPermitidos.contains(widget.dni)) {
                if(mounted) setState(() { _statusMessage = '❌ ERROR: No tienes permiso para marcar en este dispositivo.'; });
                return;
            }
        }
        
        ubicacionesPermitidasDelTrabajador = trabajadorSnap.data()?['ubicacionesPermitidas'] ?? [];
        if (ubicacionesPermitidasDelTrabajador.isEmpty) {
          if(mounted) setState(() { _statusMessage = '❌ ERROR: No tiene ubicaciones asignadas.'; });
          return;
        }
      }

      Position currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      bool isWithinAllowedLocation = false;
      String locationName = "Ubicación desconocida";

      if (!hasInternet) {
        isWithinAllowedLocation = true;
        locationName = "Ubicación no verificada (sin conexión)";
      } else {
        final LatLng userLocation = LatLng(currentPosition.latitude, currentPosition.longitude);
        final Geodesy geodesy = Geodesy();
        for (var location in _allowedLocations) {
          if (!ubicacionesPermitidasDelTrabajador.contains(location['id'])) {
            continue;
          }
          if (location['limites'] != null && (location['limites'] as List).isNotEmpty) {
            final List<LatLng> polygonPoints = (location['limites'] as List)
                .map<LatLng>((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
                .toList();
            if (polygonPoints.length >= 3 && geodesy.isGeoPointInPolygon(userLocation, polygonPoints)) {
              isWithinAllowedLocation = true;
              locationName = location['nombre'];
              break;
            }
          }
          else if (location['latitud'] != null && location['longitud'] != null) {
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
        final attendanceData = {
          'tipoMarcacion': markingType,
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
          'deviceId': _deviceId,
          'userDni': widget.dni,
          'userName': widget.nombre,
          'userArea': widget.area,
          'createdAt': DateTime.now().toIso8601String(),
          'status': hasInternet ? 'success' : 'pending_sync',
          'locationName': locationName,
        };
        if (hasInternet) {
          await FirebaseFirestore.instance.collection('asistencias').add({
            ...attendanceData,
            'timestamp': FieldValue.serverTimestamp(),
          });
        } else {
          await Hive.box('asistencias_pendientes').add(attendanceData);
        }
        if (mounted) {
          setState(() {
            _lastMarkingType = markingType;
            _statusMessage = markingType == 'Entrada'
                ? '✅ ENTRADA REGISTRADA. ¡Buen trabajo!'
                : '✅ SALIDA REGISTRADA. ¡Hasta pronto!';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage = '❌ ESTÁS FUERA DE CUALQUIER ÁREA DE TRABAJO PERMITIDA.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '❌ Ocurrió un error inesperado.';
        });
      }
      print("Error en _markAttendance: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
                const Text('Control de Asistencia', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      const Text('ESTADO ACTUAL', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 16),
                      Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login),
                            label: const Text('ENTRADA'),
                            onPressed: _isLoading || _lastMarkingType == 'Entrada' ? null : () => _markAttendance('Entrada'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade400,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.logout),
                            label: const Text('SALIDA'),
                            onPressed: _isLoading || _lastMarkingType == 'Salida' ? null : () => _markAttendance('Salida'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade400,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
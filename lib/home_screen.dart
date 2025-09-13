import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_colors.dart';
import 'package:geodesy/geodesy.dart';
import 'package:hive/hive.dart';
import 'package:flutter_security_checker/flutter_security_checker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class HomeScreen extends StatefulWidget {
  final String dni;
  final String nombre;
  final String area; // <-- AÑADE ESTA LÍNEA

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
  String _statusMessage = 'Presiona para marcar tu asistencia';
  bool _isLoading = false;
  String? _deviceId;
  List<Map<String, dynamic>> _allowedLocations = [];

  @override
  void initState() {
    super.initState();
    _loadAllowedLocations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_deviceId == null) {
      _getDeviceId();
    }
  }

  Future<void> _loadAllowedLocations() async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance.collection('ubicaciones').get();
      final locations = querySnapshot.docs.map((doc) => doc.data()).toList();
      setState(() {
        _allowedLocations = locations;
      });
      print("Ubicaciones permitidas cargadas: ${_allowedLocations.length}");
    } catch (e) {
      print("Error al cargar ubicaciones: $e");
    }
  }

  Future<void> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      final platform = Theme.of(context).platform;
      if (platform == TargetPlatform.android) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (platform == TargetPlatform.iOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      }
    } catch (e) {
      print("Error al obtener el ID del dispositivo: $e");
    }
  }

  Future<void> _logFraudulentAttempt({
    required String reason,
    Position? position,
  }) async {
    if (_deviceId == null) {
      print("No se puede registrar intento de fraude: falta deviceId");
      return;
    }
    final fraudData = {
      'timestamp': FieldValue.serverTimestamp(),
      'deviceId': _deviceId,
      'userDni': widget.dni,
      'userName': widget.nombre,
      'reason': reason,
      'reportedLatitude': position?.latitude,
      'reportedLongitude': position?.longitude,
    };
    try {
      await FirebaseFirestore.instance
          .collection('asistencias_fraudulentas')
          .add(fraudData);
      print("Intento de fraude registrado con éxito en Firestore.");
    } on FirebaseException catch (e) {
      print("ERROR DE FIREBASE al registrar fraude: ${e.code} - ${e.message}");
    } catch (e) {
      print("Error DESCONOCIDO al registrar intento de fraude: $e");
    }
  }

  Future<void> _handleMarkAttendance() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Iniciando verificación...';
    });

    try {
      // 1. VERIFICAMOS LA CONEXIÓN Y OBTENEMOS DATOS DEL TRABAJADOR SI HAY INTERNET
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet =
          connectivityResult.contains(ConnectivityResult.mobile) ||
              connectivityResult.contains(ConnectivityResult.wifi);

      List<dynamic> ubicacionesPermitidasDelTrabajador = [];
      if (hasInternet) {
        setState(() {
          _statusMessage = 'Verificando datos de trabajador...';
        });
        final trabajadorSnap = await FirebaseFirestore.instance
            .collection('trabajadores')
            .doc(widget.dni)
            .get();

        if (!trabajadorSnap.exists ||
            !(trabajadorSnap.data()?['activo'] ?? false)) {
          setState(() {
            _statusMessage = '❌ ERROR: Trabajador no encontrado o inactivo.';
          });
          return;
        }
        if (_deviceId != trabajadorSnap.data()?['deviceIdVinculado']) {
          setState(() {
            _statusMessage =
                '❌ ERROR: Dispositivo no autorizado para este DNI.';
          });
          return;
        }
        ubicacionesPermitidasDelTrabajador =
            trabajadorSnap.data()?['ubicacionesPermitidas'] ?? [];
        if (ubicacionesPermitidasDelTrabajador.isEmpty) {
          setState(() {
            _statusMessage = '❌ ERROR: No tiene ubicaciones asignadas.';
          });
          return;
        }
      } else {
        setState(() {
          _statusMessage = '🔌 Operando en modo sin conexión...';
        });
      }

      // 2. VALIDACIONES LOCALES (SEGURIDAD Y PERMISOS)
      setState(() {
        _statusMessage = 'Comprobando seguridad del dispositivo...';
      });
      final isRooted = await FlutterSecurityChecker.isRooted;
      if (isRooted) {
        await _logFraudulentAttempt(reason: 'Dispositivo rooteado');
        setState(() {
          _statusMessage = '❌ ERROR: Configuración de seguridad no permitida.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Obteniendo ubicación...';
      });
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _statusMessage = '❌ ERROR: Permiso de ubicación denegado.';
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage =
              '❌ ERROR: Permiso de ubicación denegado permanentemente.';
        });
        return;
      }

      Position currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      } catch (e) {
        setState(() {
          _statusMessage = '❌ ERROR: No se pudo obtener la ubicación a tiempo.';
        });
        return;
      }

      if (currentPosition.isMocked) {
        await _logFraudulentAttempt(
          reason: 'Ubicación simulada detectada',
          position: currentPosition,
        );
        setState(() {
          _statusMessage =
              '⚠️ Estas intentando falsificar tu ubicacion, desactivalo y vuelve a intentarlo.';
        });
        return;
      }

      // 3. LÓGICA DE VALIDACIÓN DE UBICACIÓN
      bool isWithinAllowedLocation = false;
      String locationName = "Ubicación desconocida";

      if (!hasInternet) {
        // MODO OFFLINE: Se asume que la ubicación es válida para procesar después.
        isWithinAllowedLocation = true;
        locationName = "Ubicación no verificada (sin conexión)";
      } else {
        // MODO ONLINE: Se realiza la validación completa.
        if (_allowedLocations.isEmpty) {
          setState(() {
            _statusMessage =
                '❌ ERROR: No se pudieron cargar las ubicaciones del sistema.';
          });
          return;
        }

        final Geodesy geodesy = Geodesy();
        final LatLng userLocation =
            LatLng(currentPosition.latitude, currentPosition.longitude);

        for (var location in _allowedLocations) {
          final String currentLocationName = location['nombre'];

          if (!ubicacionesPermitidasDelTrabajador
              .contains(currentLocationName)) {
            continue; // Esta ubicación no está en la lista personal del trabajador, la saltamos.
          }

          // Primero, intentamos validar por polígono
          if (location['limites'] != null &&
              (location['limites'] as List).isNotEmpty) {
            final List<LatLng> polygonPoints = (location['limites'] as List)
                .map<LatLng>((p) => LatLng(
                    (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
                .toList();
            if (polygonPoints.length >= 3 &&
                geodesy.isGeoPointInPolygon(userLocation, polygonPoints)) {
              isWithinAllowedLocation = true;
              locationName = currentLocationName;
              break;
            }
          }
          // Si no hay polígono, intentamos validar por radio
          else if (location['latitud'] != null &&
              location['longitud'] != null) {
            final double distance = Geolocator.distanceBetween(
                (location['latitud'] as num).toDouble(),
                (location['longitud'] as num).toDouble(),
                currentPosition.latitude,
                currentPosition.longitude);
            if (distance <= (location['radio'] as num? ?? 30.0).toDouble()) {
              isWithinAllowedLocation = true;
              locationName = currentLocationName;
              break;
            }
          }
        }
      }

      // 4. LÓGICA DE GUARDADO FINAL
      if (isWithinAllowedLocation) {
        if (_deviceId == null) {
          setState(() {
            _statusMessage =
                '❌ ERROR: No se pudo obtener el ID del dispositivo.';
          });
          return;
        }

        final attendanceData = {
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
          setState(() {
            _statusMessage = '✅ Conectado. Guardando en la nube...';
          });
          try {
            await FirebaseFirestore.instance.collection('asistencias').add({
              ...attendanceData,
              'timestamp': FieldValue.serverTimestamp(),
            });
            setState(() {
              _statusMessage = '✅ ¡Asistencia registrada con éxito en la nube!';
            });
          } on FirebaseException catch (e) {
            print(
                "Error de Firebase, guardando en Hive como respaldo: ${e.message}");
            setState(() {
              _statusMessage = '❌ Error de red, guardando localmente...';
            });
            await Hive.box('asistencias_pendientes').add(attendanceData);
          }
        } else {
          await Hive.box('asistencias_pendientes').add(attendanceData);
          setState(() {
            _statusMessage =
                '✅ ¡Asistencia guardada! Se sincronizará cuando tengas conexión.';
          });
        }
      } else {
        setState(() {
          _statusMessage =
              '❌ ESTÁS FUERA DE CUALQUIER ÁREA DE TRABAJO PERMITIDA.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Ocurrió un error inesperado: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Logo de la Empresa ---
                Image.asset(
                  'assets/images/image.png', // Asegúrate de que el nombre del archivo sea correcto
                  height: 80,
                ),
                const SizedBox(height: 24),

                // --- Título Principal ---
                const Text(
                  'Control de Asistencia',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 48),

                // --- Tarjeta de Estado ---
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
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'ESTADO ACTUAL',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.5, // Mejora la legibilidad
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // --- Botón de Acción ---
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _handleMarkAttendance,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: const Text('Marcar Asistencia'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

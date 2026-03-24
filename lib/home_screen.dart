// lib/home_screen.dart (VERSIÓN FINAL CON AVISO DE DÍA LIBRE)

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geodesy/geodesy.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// --- TUS IMPORTACIONES ---
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'app_colors.dart';

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
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  // --- VARIABLES DE ESTADO ---
  String _statusMessage = 'Cargando datos...';
  bool _isLoading = true;
  String? _deviceId;
  List<Map<String, dynamic>> _allowedLocations = [];
  String _lastMarkingType = 'Salida';

  // --- VARIABLES DE HORARIO ---
  bool _showScheduleCard = false;
  bool _esPorHoras = false;
  double _metaHoras = 0.0;

  String _horaEntrada = '--:--';
  String _horaSalida = '--:--';
  bool _esTardanza = false;
  String _mensajeAviso = '';

  final String _apiUrl = 'https://ceneris-web-oror.onrender.com/api';

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi)) {
        _syncPendingAttendances();
        _fetchInitialDataFromBackend();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _getDeviceId();
    await _fetchInitialDataFromBackend();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    // Simplemente abrimos la caja fuerte y leemos el ID que el Login creó
    _deviceId = prefs.getString('unique_device_id');
    
    // (Opcional) Un print para que lo veas en tu terminal de VS Code y confirmes que es el UUID largo
    print('📱 ID recuperado en la pantalla Home: $_deviceId');
  }

  Future<void> _syncPendingAttendances() async {
    var box = Hive.box('asistencias_pendientes');
    if (box.isEmpty) return;
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    final Map<dynamic, dynamic> rawMap = box.toMap();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    for (var key in rawMap.keys) {
      final data = rawMap[key];
      try {
        await http.post(
          Uri.parse('$_apiUrl/asistencias/registrar/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token'
          },
          body: json.encode(data),
        );
        await box.delete(key);
      } catch (e) {
        break;
      }
    }
  }

  Future<void> _fetchInitialDataFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token == null) {
      _showErrorAndLogout('Sesión inválida.');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/trabajador/estado/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        await prefs.setString('cached_config', json.encode(data));
        _applyBackendData(data);
      } else {
        _loadCachedConfig(prefs);
      }
    } catch (e) {
      _loadCachedConfig(prefs);
    }
  }

  void _applyBackendData(Map<String, dynamic> data) {
    final newLastMarkingType = data['ultimoTipoMarcacion'] ?? 'Salida';
    final locationsData = data['ubicacionesPermitidas'] as List;

    final bool tieneHorario = data['tiene_horario'] ?? false;
    final bool esPorHoras = data['es_por_horas'] ?? false;
    final double metaHoras =
        double.tryParse(data['meta_horas'].toString()) ?? 0.0;

    final String? hEntrada = data['horario_entrada'];
    final String? hSalida = data['horario_salida'];
    final esTarde = data['es_tardanza'] ?? false;
    final aviso = data['mensaje_aviso'] ?? '';

    final newStatusMessage = newLastMarkingType == 'Entrada'
        ? '✅ DENTRO. Jornada en curso.'
        : 'Listo para iniciar.';

    if (mounted) {
      setState(() {
        _lastMarkingType = newLastMarkingType;
        _statusMessage = newStatusMessage;
        _allowedLocations = List<Map<String, dynamic>>.from(locationsData);

        _showScheduleCard = tieneHorario;
        _esPorHoras = esPorHoras;
        _metaHoras = metaHoras;

        _horaEntrada = hEntrada ?? '--:--';
        _horaSalida = hSalida ?? '--:--';
        _esTardanza = esTarde;
        _mensajeAviso = aviso;
      });
    }
  }

  void _loadCachedConfig(SharedPreferences prefs) {
    final cachedString = prefs.getString('cached_config');
    if (cachedString != null) {
      final data = json.decode(cachedString);
      _applyBackendData(data);
      if (mounted) setState(() => _statusMessage = '⚠️ Modo Offline.');
    } else {
      if (mounted) setState(() => _statusMessage = '❌ Sin conexión.');
    }
  }

  Future<void> _markAttendance(String markingType) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Verificando ubicación...';
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      bool hasInternet =
          connectivityResult.contains(ConnectivityResult.mobile) ||
              connectivityResult.contains(ConnectivityResult.wifi);

      if (!await _ensureLocationPermissionAndService()) return;

      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (pos.isMocked) {
        if (mounted)
          setState(() => _statusMessage = '❌ Ubicación falsa detectada.');
        return;
      }

      if (mounted) setState(() => _statusMessage = 'Validando zona...');
      bool isAllowed = false;
      String locName = "Desconocida";

      if (!hasInternet) {
        isAllowed = true;
        locName = "Offline";
      } else {
        final LatLng userLoc = LatLng(pos.latitude, pos.longitude);
        final Geodesy geodesy = Geodesy();

        for (var loc in _allowedLocations) {
          if (loc['limites'] != null && (loc['limites'] as List).isNotEmpty) {
            final List<LatLng> poly = (loc['limites'] as List)
                .map<LatLng>((p) => LatLng(
                    (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
                .toList();
            if (poly.length >= 3 &&
                geodesy.isGeoPointInPolygon(userLoc, poly)) {
              isAllowed = true;
              locName = loc['nombre'];
              break;
            }
          } else if (loc['latitud'] != null && loc['longitud'] != null) {
            final double dist = Geolocator.distanceBetween(
                (loc['latitud'] as num).toDouble(),
                (loc['longitud'] as num).toDouble(),
                pos.latitude,
                pos.longitude);
            if (dist <= (loc['radio'] as num? ?? 50.0).toDouble()) {
              isAllowed = true;
              locName = loc['nombre'];
              break;
            }
          }
        }
      }

      if (isAllowed) {
        final data = {
          'tipo_marcacion': markingType,
          'latitud': pos.latitude,
          'longitud': pos.longitude,
          'device_id': _deviceId,
          'nombre_ubicacion': locName,
          'timestamp': DateTime.now().toIso8601String(),
        };

        if (hasInternet) {
          await _postAttendanceToBackend(data);
        } else {
          await Hive.box('asistencias_pendientes').add(data);
          if (mounted)
            setState(() {
              _lastMarkingType = markingType;
              _statusMessage = '✅ Guardado Offline.';
            });
        }
      } else {
        if (mounted) setState(() => _statusMessage = '❌ Estás fuera del área.');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '❌ Error inesperado.');
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
          'Authorization': 'Bearer $token'
        },
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          setState(() {
            _lastMarkingType = data['tipo_marcacion'];
            _statusMessage =
                _lastMarkingType == 'Entrada' ? '✅ ENTRADA OK' : '✅ SALIDA OK';
            _fetchInitialDataFromBackend();
          });
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        if (mounted)
          setState(
              () => _statusMessage = '❌ ${errorData['detail'] ?? 'Error'}');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '❌ Error de red.');
    }
  }

  Future<bool> _ensureLocationPermissionAndService() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _statusMessage = 'Encienda GPS');
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  void _showErrorAndLogout(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _logout();
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

  // ==========================================
  // UI PRINCIPAL
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. CABECERA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Control de',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500)),
                      Text('Asistencia',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text)),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ]),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.primary, size: 20),
                      onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (context) => const DashboardScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 2. SECCIÓN DINÁMICA: ¿HAY TURNO?
              if (_showScheduleCard) ...[
                if (_esPorHoras)
                  _buildCardPorHoras() // AZUL
                else
                  _buildCardHorarioFijo(), // VERDE/ROJO
              ] else ...[
                _buildCardDiaLibre(), // GRIS (Día libre)
              ],

              const SizedBox(height: 20),

              // 3. TARJETA DE ESTADO (GPS)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.08),
                          spreadRadius: 2,
                          blurRadius: 15,
                          offset: const Offset(0, 5))
                    ]),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _statusMessage.contains('❌')
                            ? Colors.red.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.location_on,
                          size: 24,
                          color: _statusMessage.contains('❌')
                              ? Colors.red
                              : Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('UBICACIÓN',
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_statusMessage,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2)),
                        ],
                      ),
                    )
                  ],
                ),
              ),

              const Spacer(),

              // 4. BOTONES
              _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : Row(
                      children: [
                        Expanded(
                            child: _ActionCard(
                                label: 'ENTRADA',
                                icon: Icons.login_rounded,
                                color: Colors.green,
                                isEnabled: _lastMarkingType != 'Entrada',
                                onTap: () => _markAttendance('Entrada'))),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _ActionCard(
                                label: 'SALIDA',
                                icon: Icons.logout_rounded,
                                color: Colors.redAccent,
                                isEnabled: _lastMarkingType != 'Salida',
                                onTap: () => _markAttendance('Salida'))),
                      ],
                    ),

              const SizedBox(height: 10),
              Center(
                  child: Text("Área: ${widget.area}",
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET 1: DÍA LIBRE ---
  Widget _buildCardDiaLibre() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.weekend_rounded,
              size: 50, color: Colors.blueGrey.shade200),
          const SizedBox(height: 15),
          const Text(
            "Sin Turno Programado",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87),
          ),
          const SizedBox(height: 8),
          const Text(
            "Hoy no tienes horarios asignados en el sistema.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // --- WIDGET 2: JORNADA POR HORAS ---
  Widget _buildCardPorHoras() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.blue.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('⏱️ Jornada Flexible',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200)),
                child: const Text('POR HORAS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue)),
              )
            ],
          ),
          const SizedBox(height: 15),
          Column(
            children: [
              const Text("Meta de hoy",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text("${_metaHoras.toStringAsFixed(1)} Horas",
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 10),
          Text(_mensajeAviso,
              style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.blueGrey)),
        ],
      ),
    );
  }

  // --- WIDGET 3: HORARIO FIJO ---
  Widget _buildCardHorarioFijo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📅 Horario Fijo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color:
                        _esTardanza ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _esTardanza
                            ? Colors.red.shade200
                            : Colors.green.shade200)),
                child: Row(
                  children: [
                    Icon(
                        _esTardanza
                            ? Icons.warning_rounded
                            : Icons.check_circle_rounded,
                        size: 14,
                        color: _esTardanza ? Colors.red : Colors.green),
                    const SizedBox(width: 6),
                    Text(_esTardanza ? 'TARDANZA' : 'A TIEMPO',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _esTardanza
                                ? Colors.red.shade700
                                : Colors.green.shade700)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTimeColumn(
                  'Entrada', _horaEntrada, Icons.wb_sunny_outlined),
              Icon(Icons.arrow_forward_rounded,
                  color: Colors.grey.shade300, size: 20),
              _buildTimeColumn(
                  'Salida', _horaSalida, Icons.nights_stay_outlined),
            ],
          ),
          const SizedBox(height: 8),
          Text(_mensajeAviso,
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: _esTardanza ? Colors.redAccent : Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(String label, String time, IconData icon) {
    return Column(children: [
      Icon(icon, size: 20, color: Colors.grey.shade400),
      const SizedBox(height: 4),
      Text(time,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text)),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
    ]);
  }
}

class _ActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isEnabled;
  final VoidCallback onTap;
  const _ActionCard(
      {required this.label,
      required this.icon,
      required this.color,
      required this.isEnabled,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isEnabled ? 1.0 : 0.4,
            child: Container(
                height: 150,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: isEnabled
                        ? Border.all(color: color.withOpacity(0.3), width: 2)
                        : null,
                    boxShadow: [
                      if (isEnabled)
                        BoxShadow(
                            color: color.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 8))
                    ]),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                          child: Icon(icon, color: Colors.white, size: 32)),
                      const SizedBox(height: 14),
                      Text(label,
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1))
                    ]))));
  }
}

// lib/home_screen.dart (VERSIÓN FINAL CON AVISO DE DÍA LIBRE)

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geodesy/geodesy.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// --- TUS IMPORTACIONES ---
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'app_colors.dart';
import 'config/api_config.dart';
import 'sync_service.dart';
import 'services/auth_token_provider.dart';
import 'services/network_status.dart';
import 'services/user_sync_service.dart';

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription<void>? _connectivitySubscription;

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

  // --- CAV-64: DÍA FERIADO ---
  bool _esFeriado = false;
  String _nombreFeriado = '';

  final String _apiUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreen();

    // Stream unificado: reacciona a cualquier interfaz activa (datos móviles,
    // Wi-Fi, hotspot compartido, ethernet o VPN), no solo a `mobile`/`wifi`.
    _connectivitySubscription =
        NetworkStatus.instance.onConnectivityRestored.listen((_) {
      SyncService.instance.scheduleSync();
      _fetchInitialDataFromBackend();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Volver del background es el momento típico en que el usuario ya
    // recuperó señal: el evento de conectividad pudo ocurrir con la app
    // suspendida, sin que nadie lo escuchara.
    if (state == AppLifecycleState.resumed) {
      NetworkStatus.instance.invalidateCache();
      SyncService.instance.scheduleSync();
    }
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

  /// Encola una marca para que la suba [SyncService].
  ///
  /// Antes existía aquí un segundo sincronizador propio de la pantalla que
  /// borraba el registro de Hive sin mirar el `statusCode`: con el token
  /// caducado, Django respondía 401 y la marca se destruía en silencio.
  /// Ahora la pantalla solo encola; subir (y decidir qué se borra) es
  /// responsabilidad exclusiva del worker.
  Future<void> _encolarMarca(
    Map<String, dynamic> data, {
    required String mensaje,
  }) async {
    final registro = Map<String, dynamic>.from(data);
    // Clave de idempotencia: sobrevive a los reintentos, de modo que una
    // petición que sí llegó pero cuya respuesta se perdió no genere una
    // marca duplicada.
    registro.putIfAbsent('client_uuid', () => const Uuid().v4());
    registro['intentos'] = 0;

    await Hive.box(SyncService.pendingBoxName).add(registro);
    SyncService.instance.scheduleSync();

    if (mounted) {
      setState(() {
        if (registro['is_fraud'] != true) {
          _lastMarkingType = registro['tipo_marcacion'];
        }
        _statusMessage = mensaje;
      });
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
      ).timeout(const Duration(seconds: 45));

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

    // CAV-182 (cliente): sincroniza en segundo plano la lista de usuarios
    // autorizados. No debe bloquear ni romper la carga del dashboard si
    // falla (por ejemplo, sin conexión): solo se registra el error.
    unawaited(_syncAuthorizedUsers(token));
  }

  Future<void> _syncAuthorizedUsers(String token) async {
    try {
      final syncService = UserSyncService(apiUrl: _apiUrl);
      await syncService.sync(token: token);
    } catch (e) {
      // Sincronización silenciosa: si falla (sin conexión, checksum
      // inválido, etc.) simplemente se reintentará la próxima vez que
      // se abra esta pantalla, sin afectar el resto de la app.
      debugPrint('CAV-182: no se pudo sincronizar usuarios autorizados: $e');
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

    // CAV-64: El backend marca si el día es feriado. Aceptamos varias claves
    // por compatibilidad con la respuesta del API (es_feriado / nombre_feriado).
    final bool esFeriado = data['es_feriado'] ?? false;
    final String nombreFeriado =
        (data['nombre_feriado'] ?? data['mensaje_feriado'] ?? 'Día Feriado')
            .toString();

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

        _esFeriado = esFeriado;
        _nombreFeriado = nombreFeriado;
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
      // Chequeo ACTIVO, no el estado de la interfaz: estar asociado a un
      // hotspot compartido sin datos, a un router sin servicio o a un portal
      // cautivo también se reporta como "wifi conectado".
      final bool hasInternet =
          await NetworkStatus.instance.hasRealInternet(force: true);

      if (!await _ensureLocationPermissionAndService()) return;

      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
          
      // ==============================================================
      // 🚨 1. ESCUDO ANTI-FRAUDE: Detectar y acusar con Django
      // ==============================================================
      if (pos.isMocked) {
        if (mounted) {
          setState(() => _statusMessage = '❌ Ubicación falsa detectada.');
        }

        // Si hay internet, le avisamos a Django inmediatamente
        if (hasInternet) {
          final fraudData = {
            'tipo_marcacion': markingType,
            'latitud': pos.latitude,
            'longitud': pos.longitude,
            'device_id': _deviceId,
            'nombre_ubicacion': 'Fake GPS',
            'timestamp': DateTime.now().toIso8601String(),
            // ---> ESTAS DOS LÍNEAS ACTIVAN LA ALARMA EN DJANGO <---
            'is_fraud': true, 
            'reason': 'Uso de Fake GPS / Ubicación simulada',
          };
          
          // Enviamos el fraude usando tu misma función
          await _postAttendanceToBackend(fraudData);
        }
        
        return; // Ahora sí, cortamos la ejecución para que no marque normal
      }
      // ==============================================================

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

      // ==============================================================
      // --- 2. MARCAR ASISTENCIA NORMAL ---
      // ==============================================================
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
          await _encolarMarca(data, mensaje: '✅ Guardado Offline.');
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
    final token = await AuthTokenProvider().getAccessToken();
    // El mismo `client_uuid` viaja en el camino online: si la respuesta se
    // pierde y la marca acaba encolada, el backend puede reconocerla.
    final payload = Map<String, dynamic>.from(data)
      ..putIfAbsent('client_uuid', () => const Uuid().v4());

    try {
      final response = await http
          .post(
            Uri.parse('$_apiUrl/asistencias/registrar/'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _lastMarkingType = payload['tipo_marcacion'];
            _statusMessage =
                _lastMarkingType == 'Entrada' ? '✅ ENTRADA OK' : '✅ SALIDA OK';
            _fetchInitialDataFromBackend();
          });
        }
        return;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Sesión caducada en pleno envío: la marca NO se pierde. El worker
        // renovará el token con el refresh y la subirá.
        await _encolarMarca(payload,
            mensaje: '⏳ Sesión caducada. Marca guardada, se subirá sola.');
        return;
      }

      final errorData = json.decode(utf8.decode(response.bodyBytes));
      if (mounted) {
        setState(() => _statusMessage = '❌ ${errorData['detail'] ?? 'Error'}');
      }
    } catch (e) {
      // La conexión se cayó entre la verificación y el envío (o el servidor
      // no respondió a tiempo). Encolamos en vez de perder la marcación.
      await _encolarMarca(payload,
          mensaje: '⚠️ Sin conexión al enviar. Guardado offline.');
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
    // El refresh vive en el almacén cifrado, no en prefs: hay que borrarlo
    // aparte para no dejar una sesión renovable tras el logout.
    await AuthTokenProvider().clearRefreshToken();
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

              // CAV-64: BANNER DE DÍA FERIADO
              if (_esFeriado) ...[
                _buildBannerFeriado(),
                const SizedBox(height: 16),
              ],

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

  // --- CAV-64: BANNER DE DÍA FERIADO ---
  Widget _buildBannerFeriado() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.purple.shade500, Colors.deepPurple.shade400],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.celebration_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DÍA FERIADO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _nombreFeriado,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
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

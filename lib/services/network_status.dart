import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'trusted_clock.dart';

/// Estado de red "omnicanal" para la sincronización offline-first.
///
/// El problema que resuelve: `connectivity_plus` solo informa qué interfaz
/// declara el sistema operativo (`wifi`, `mobile`, `vpn`, ...), no si existe
/// salida real a Internet. El código anterior además filtraba con una lista
/// blanca (`mobile || wifi`), lo que producía:
///
///  * Falsos negativos: una VPN corporativa puede reportarse solo como
///    `ConnectivityResult.vpn` y la app se creía sin conexión.
///  * Falsos positivos: `wifi` significa "asociado a un punto de acceso".
///    Un hotspot compartido desde otro celular SIN datos, un router sin
///    servicio o un portal cautivo reportan `wifi` sin tener Internet.
///
/// Aquí la regla es al revés: hay interfaz si el SO NO reporta `none`
/// (cubre datos móviles, Wi-Fi, anclaje/hotspot, ethernet, VPN y `other`),
/// y sobre esa señal se hace un chequeo ACTIVO contra la propia API.
class NetworkStatus {
  NetworkStatus({
    http.Client? httpClient,
    Connectivity? connectivity,
    String? apiUrl,
    Duration debounce = const Duration(milliseconds: 1500),
    Duration cacheTtl = const Duration(seconds: 5),
    Duration probeTimeout = const Duration(seconds: 8),
  })  : _httpClient = httpClient ?? http.Client(),
        _connectivity = connectivity ?? Connectivity(),
        _apiUrl = apiUrl ?? ApiConfig.baseUrl,
        _debounce = debounce,
        _cacheTtl = cacheTtl,
        _probeTimeout = probeTimeout;

  /// Instancia compartida por la app (la usan `SyncService` y `HomeScreen`).
  static final NetworkStatus instance = NetworkStatus();

  final http.Client _httpClient;
  final Connectivity _connectivity;
  final String _apiUrl;
  final Duration _debounce;
  final Duration _cacheTtl;
  final Duration _probeTimeout;

  StreamController<void>? _controller;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounceTimer;

  bool? _cachedResult;
  DateTime? _cachedAt;

  /// Emite cada vez que vuelve a haber una interfaz de red activa, sea cual
  /// sea (datos móviles, Wi-Fi, hotspot compartido, ethernet o VPN).
  ///
  /// Durante una transición en caliente (por ejemplo pasar de datos móviles a
  /// Wi-Fi) el sistema emite varios eventos en menos de un segundo; el
  /// debounce los colapsa en una sola notificación para no disparar
  /// sincronizaciones solapadas.
  Stream<void> get onConnectivityRestored {
    _controller ??= StreamController<void>.broadcast();
    _subscription ??= _connectivity.onConnectivityChanged.listen(_handleChange);
    return _controller!.stream;
  }

  void _handleChange(List<ConnectivityResult> results) {
    // Cualquier cambio de interfaz invalida el resultado cacheado: puede que
    // el hotspot al que acabamos de saltar no tenga datos.
    invalidateCache();

    _debounceTimer?.cancel();
    if (!hasActiveInterface(results)) return;

    _debounceTimer = Timer(_debounce, () {
      final controller = _controller;
      if (controller != null && !controller.isClosed) controller.add(null);
    });
  }

  /// `true` si el SO reporta al menos una interfaz distinta de `none`.
  /// Deliberadamente NO es una lista blanca: cualquier interfaz cuenta.
  static bool hasActiveInterface(List<ConnectivityResult> results) {
    return results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
  }

  /// `true` si el SO reporta alguna interfaz activa en este momento.
  Future<bool> hasActiveInterfaceNow() async {
    try {
      return hasActiveInterface(await _connectivity.checkConnectivity());
    } catch (_) {
      // Si el plugin falla, no bloqueamos: dejamos que decida el chequeo activo.
      return true;
    }
  }

  /// Chequeo ACTIVO: confirma que la API es realmente alcanzable.
  ///
  /// Se usa un `HEAD` sobre HTTPS contra la propia API en lugar de un simple
  /// DNS lookup porque un portal cautivo sí resuelve DNS (e incluso responde
  /// HTTP), pero no puede completar el handshake TLS contra nuestro dominio.
  /// Cualquier respuesta del servidor —incluido un 4xx/5xx— demuestra que hubo
  /// salida real a Internet; solo las excepciones de socket/timeout cuentan
  /// como "sin conexión".
  Future<bool> hasRealInternet({bool force = false}) async {
    final cachedAt = _cachedAt;
    if (!force &&
        _cachedResult != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cachedResult!;
    }

    final result = await _probe();
    _cachedResult = result;
    _cachedAt = DateTime.now();
    return result;
  }

  Future<bool> _probe() async {
    // Atajo: en modo avión no tiene sentido esperar el timeout completo.
    if (!await hasActiveInterfaceNow()) return false;

    try {
      final response =
          await _httpClient.head(Uri.parse(_apiUrl)).timeout(_probeTimeout);

      // Antifraude de reloj: esta respuesta trae la hora del servidor en su
      // cabecera `Date`. Es el mejor momento para anclarla contra el reloj
      // monotónico del equipo, porque este chequeo corre SIN token (los
      // demás anclajes exigen sesión, y un login offline nunca genera una)
      // y es lo último que se ejecuta antes de que el trabajador se quede
      // sin señal. No cuesta ninguna petición extra: reusa esta.
      await TrustedClock.instance.anclarConRespuesta(response);

      return true;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } on HandshakeException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void invalidateCache() {
    _cachedResult = null;
    _cachedAt = null;
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _controller?.close();
    _controller = null;
  }
}

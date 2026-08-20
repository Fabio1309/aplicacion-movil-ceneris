import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'config/api_config.dart';
import 'services/auth_token_provider.dart';
import 'services/network_status.dart';
import 'services/offline_login_event_queue.dart';

/// Resultado de intentar enviar UN registro de la cola.
enum _SendStatus {
  /// El servidor lo aceptó: se puede borrar de la cola.
  accepted,

  /// El servidor ya lo tenía (reintento de una petición que sí llegó):
  /// también se borra, es el caso feliz de la idempotencia.
  duplicate,

  /// El token no sirve. No se borra nada: hay que renovar la sesión.
  unauthorized,

  /// El servidor lo rechazó por contenido inválido. Reintentarlo tal cual
  /// nunca va a funcionar.
  rejected,

  /// Fallo transitorio (sin red, timeout, 5xx). Se conserva y se reintenta.
  retryable,
}

class _SendResult {
  const _SendResult(this.status, [this.detail]);
  final _SendStatus status;
  final String? detail;
}

enum _CycleOutcome { completed, retryable, authExpired }

/// Worker único de sincronización de la cola offline de asistencias.
///
/// Reemplaza la implementación anterior, que tenía tres fallos encadenados:
///
///  1. Leía un esquema (`createdAt`/`latitude`/`longitude`) que nadie escribía
///     —la pantalla de marcación encola `timestamp`/`latitud`/`longitud`—, así
///     que lanzaba un `TypeError` ANTES del `try`. Como `_isSyncing` se ponía
///     en `true` sin `finally`, la bandera quedaba trabada para siempre y toda
///     sincronización posterior salía por "ya en progreso": un deadlock
///     permanente durante toda la vida del proceso.
///  2. Enviaba las marcas a Firestore, cuando la fuente de verdad es el
///     backend Django (es de donde lee el historial).
///  3. El camino alternativo que sí llegaba a Django borraba el registro sin
///     mirar el `statusCode`, de modo que un token caducado (401) destruía la
///     marca en silencio.
class SyncService {
  SyncService({
    String? apiUrl,
    http.Client? httpClient,
    AuthTokenProvider? authTokenProvider,
    OfflineLoginEventQueue? offlineLoginQueue,
    Future<bool> Function()? connectivityProbe,
    Stream<void>? connectivityRestored,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    Duration heartbeat = const Duration(minutes: 15),
  })  : _apiUrl = apiUrl ?? ApiConfig.baseUrl,
        _httpClient = httpClient ?? http.Client(),
        _auth = authTokenProvider ?? AuthTokenProvider(),
        _offlineLoginQueue = offlineLoginQueue ?? OfflineLoginEventQueue(),
        _connectivityProbe =
            connectivityProbe ?? NetworkStatus.instance.hasRealInternet,
        _connectivityRestored = connectivityRestored,
        _requestTimeout = requestTimeout,
        _baseBackoff = baseBackoff,
        _maxBackoff = maxBackoff,
        _heartbeat = heartbeat;

  /// Instancia compartida: la app necesita UN solo worker, y hay que poder
  /// dispararlo desde la UI (tras marcar offline o al volver del background).
  static final SyncService instance = SyncService();

  static const pendingBoxName = 'asistencias_pendientes';
  static const rejectedBoxName = 'asistencias_rechazadas';

  /// Tras este número de rechazos definitivos, el registro se aparta a
  /// [rejectedBoxName] para revisión manual en vez de bloquear la cola.
  static const maxRejectionAttempts = 5;

  static const _maxBackoffCycles = 6;

  final String _apiUrl;
  final http.Client _httpClient;
  final AuthTokenProvider _auth;
  final OfflineLoginEventQueue _offlineLoginQueue;
  final Future<bool> Function() _connectivityProbe;
  final Stream<void>? _connectivityRestored;
  final Duration _requestTimeout;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final Duration _heartbeat;

  final Uuid _uuid = const Uuid();
  final Random _random = Random();

  bool _isSyncing = false;
  bool _started = false;
  int _backoffAttempt = 0;
  Timer? _backoffTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<void>? _connectivitySubscription;

  /// Cantidad de marcas pendientes, para que la UI pueda mostrarlo.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// `true` cuando la sesión caducó y el refresh tampoco funcionó: la cola
  /// queda intacta, pero hace falta que el usuario vuelva a iniciar sesión.
  final ValueNotifier<bool> requiresReLogin = ValueNotifier<bool>(false);

  Box get _pendingBox => Hive.box(pendingBoxName);
  Box get _rejectedBox => Hive.box(rejectedBoxName);

  void startListening() {
    if (_started) return;
    _started = true;

    // Escuchamos el stream unificado: reacciona a CUALQUIER interfaz activa
    // (datos móviles, Wi-Fi, hotspot compartido, ethernet, VPN) y ya viene
    // con debounce para las transiciones en caliente.
    final restored =
        _connectivityRestored ?? NetworkStatus.instance.onConnectivityRestored;
    _connectivitySubscription = restored.listen((_) {
      // Red nueva: el backoff arranca de cero.
      _backoffAttempt = 0;
      _backoffTimer?.cancel();
      unawaited(syncNow());
    });

    // Red de seguridad: un hotspot que estaba sin datos y de pronto los
    // recupera no genera ningún evento de conectividad.
    _heartbeatTimer = Timer.periodic(_heartbeat, (_) {
      if (_pendingBox.isNotEmpty || _offlineLoginQueue.hayPendientes) {
        unawaited(syncNow());
      }
    });

    unawaited(syncNow());
  }

  /// Dispara una sincronización inmediata (arranque, cambio de red, vuelta
  /// del background o justo después de guardar una marca offline).
  Future<void> syncNow() async {
    await syncPendingAttendances();
    await syncPendingOfflineLoginEvents();
  }

  /// Igual que [syncNow], pero sin bloquear a quien llama.
  void scheduleSync() => unawaited(syncNow());

  Future<void> syncPendingAttendances() async {
    if (_isSyncing) return;
    _refreshPendingCount();
    if (_pendingBox.isEmpty) return;

    _isSyncing = true;
    try {
      // Chequeo activo: evita quemar reintentos contra un hotspot sin datos
      // o un portal cautivo, que el SO igual reporta como "wifi conectado".
      if (!await _connectivityProbe()) {
        debugPrint('SyncService: interfaz activa pero sin salida real a '
            'Internet. Se conserva la cola.');
        return;
      }

      final outcome = await _drainQueue();
      switch (outcome) {
        case _CycleOutcome.completed:
          _backoffAttempt = 0;
          requiresReLogin.value = false;
          break;
        case _CycleOutcome.retryable:
          requiresReLogin.value = false;
          _scheduleRetry();
          break;
        case _CycleOutcome.authExpired:
          // La cola queda intacta a propósito: reintentar con el mismo token
          // muerto solo gastaría batería. Se retoma tras el re-login.
          requiresReLogin.value = true;
          debugPrint('SyncService: sesión caducada y refresh no disponible. '
              'Cola preservada (${_pendingBox.length} marcas).');
          break;
      }
    } catch (e, stack) {
      // Cinturón de seguridad: nada puede escapar de aquí. El `finally` de
      // abajo es lo único que garantiza que el worker no quede trabado, que
      // fue exactamente el bug original.
      debugPrint('SyncService: error inesperado al sincronizar: $e\n$stack');
      _scheduleRetry();
    } finally {
      _isSyncing = false;
      _refreshPendingCount();
    }
  }

  Future<_CycleOutcome> _drainQueue() async {
    var tokenGuardado = await _auth.getAccessToken();
    if (tokenGuardado == null || tokenGuardado.isEmpty) {
      tokenGuardado = await _auth.refreshAccessToken();
      if (tokenGuardado == null) return _CycleOutcome.authExpired;
    }

    var token = tokenGuardado;
    var yaSeRefresco = false;
    var outcome = _CycleOutcome.completed;

    for (final key in _pendingBox.keys.toList()) {
      final raw = _pendingBox.get(key);
      if (raw == null) continue;
      final record = Map<String, dynamic>.from(raw as Map);

      // Idempotencia: el `client_uuid` debe sobrevivir a los reintentos, así
      // que se persiste. Este backfill cubre las marcas que quedaron
      // encoladas por versiones anteriores de la app.
      if (record['client_uuid'] == null) {
        record['client_uuid'] = _uuid.v4();
        await _pendingBox.put(key, record);
      }

      var result = await _send(record, token);

      if (result.status == _SendStatus.unauthorized && !yaSeRefresco) {
        yaSeRefresco = true;
        final renovado = await _auth.refreshAccessToken();
        if (renovado == null) return _CycleOutcome.authExpired;
        token = renovado;
        result = await _send(record, token);
      }

      switch (result.status) {
        case _SendStatus.accepted:
        case _SendStatus.duplicate:
          await _pendingBox.delete(key);
          break;
        case _SendStatus.unauthorized:
          return _CycleOutcome.authExpired;
        case _SendStatus.rejected:
          await _registrarRechazo(key, record, result.detail);
          break;
        case _SendStatus.retryable:
          outcome = _CycleOutcome.retryable;
          break;
      }
    }

    return outcome;
  }

  Future<_SendResult> _send(Map<String, dynamic> record, String token) async {
    // Los campos de control son locales: no se envían al backend.
    final payload = Map<String, dynamic>.from(record)
      ..remove('intentos')
      ..remove('ultimo_error');

    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_apiUrl/asistencias/registrar/'),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(payload),
          )
          .timeout(_requestTimeout);

      return _classify(response);
    } on TimeoutException {
      return const _SendResult(_SendStatus.retryable, 'timeout');
    } on SocketException catch (e) {
      return _SendResult(_SendStatus.retryable, e.message);
    } on http.ClientException catch (e) {
      return _SendResult(_SendStatus.retryable, e.message);
    } catch (e) {
      return _SendResult(_SendStatus.retryable, e.toString());
    }
  }

  _SendResult _classify(http.Response response) {
    final code = response.statusCode;

    if (code == 200 || code == 201) {
      return const _SendResult(_SendStatus.accepted);
    }
    if (code == 409) return const _SendResult(_SendStatus.duplicate);

    // 401 y 403: SimpleJWT devuelve uno u otro según haya o no cabecera de
    // autenticación válida. En ambos casos la respuesta es renovar, no borrar.
    if (code == 401 || code == 403) {
      return const _SendResult(_SendStatus.unauthorized);
    }

    // Transitorios de servidor o infraestructura: se reintentan con backoff.
    if (code >= 500 || code == 404 || code == 408 || code == 429) {
      return _SendResult(_SendStatus.retryable, 'HTTP $code');
    }

    final cuerpo = _bodyAsText(response).toLowerCase();
    if (code == 400 &&
        (cuerpo.contains('duplicad') ||
            cuerpo.contains('ya existe') ||
            cuerpo.contains('ya registrad') ||
            cuerpo.contains('already exists') ||
            cuerpo.contains('unique'))) {
      return const _SendResult(_SendStatus.duplicate);
    }

    return _SendResult(_SendStatus.rejected, 'HTTP $code: $cuerpo');
  }

  String _bodyAsText(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  /// Un registro que el servidor rechaza por contenido no se puede reenviar
  /// tal cual, pero tampoco se descarta a la ligera: se le cuentan los
  /// intentos y solo tras [maxRejectionAttempts] se aparta a una caja de
  /// revisión, para que no bloquee al resto de la cola.
  Future<void> _registrarRechazo(
    dynamic key,
    Map<String, dynamic> record,
    String? detalle,
  ) async {
    final intentos = (record['intentos'] as int? ?? 0) + 1;
    record['intentos'] = intentos;
    record['ultimo_error'] = detalle ?? 'rechazado por el servidor';

    if (intentos >= maxRejectionAttempts) {
      record['descartado_en'] = DateTime.now().toIso8601String();
      if (Hive.isBoxOpen(rejectedBoxName)) {
        await _rejectedBox.add(record);
      }
      await _pendingBox.delete(key);
      debugPrint('SyncService: marca $key apartada tras $intentos rechazos '
          '(${record['ultimo_error']}).');
      return;
    }

    await _pendingBox.put(key, record);
  }

  void _scheduleRetry() {
    if (_backoffAttempt >= _maxBackoffCycles) {
      debugPrint('SyncService: backoff agotado; se espera al próximo cambio '
          'de red o al heartbeat.');
      return;
    }

    final exponente = _backoffAttempt;
    _backoffAttempt++;

    var millis = _baseBackoff.inMilliseconds * pow(2, exponente).toInt();
    if (millis > _maxBackoff.inMilliseconds) {
      millis = _maxBackoff.inMilliseconds;
    }
    // Jitter de hasta +30% para que no sincronicen a la vez todos los
    // dispositivos de una obra cuando vuelve la señal.
    final jitter = _random.nextInt((millis * 0.3).round() + 1);
    final delay = Duration(milliseconds: millis + jitter);

    debugPrint('SyncService: reintento $_backoffAttempt/$_maxBackoffCycles '
        'en ${delay.inSeconds}s.');

    _backoffTimer?.cancel();
    _backoffTimer = Timer(delay, () => unawaited(syncPendingAttendances()));
  }

  void _refreshPendingCount() {
    if (!Hive.isBoxOpen(pendingBoxName)) return;
    pendingCount.value = _pendingBox.length;
  }

  /// CAV-83: al volver la conexión, reporta a Django los logins offline
  /// que quedaron pendientes en la cola local (CAV-81/82).
  Future<void> syncPendingOfflineLoginEvents() async {
    if (!_offlineLoginQueue.hayPendientes) return;

    final token = await _auth.getAccessToken();
    if (token == null) return; // Sin sesión válida, no hay con qué reportar.

    try {
      await _offlineLoginQueue.flush(apiUrl: _apiUrl, token: token);
    } catch (e) {
      debugPrint('SyncService: no se pudo sincronizar login offline: $e');
    }
  }

  Future<void> dispose() async {
    _backoffTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _started = false;
  }
}

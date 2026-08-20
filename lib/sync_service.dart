import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/api_config.dart';
import 'services/offline_login_event_queue.dart';
import 'services/pending_attendance_queue.dart';

/// Orquestador unico de todo lo que quedo pendiente de subir mientras el
/// trabajador estuvo sin señal: marcaciones de asistencia (CAV-83) y
/// eventos de login offline (CAV-81/82/83).
///
/// Se usa siempre a traves de [SyncService.instance]: el candado
/// `_isSyncing` solo sirve si toda la app comparte la misma instancia.
class SyncService {
  SyncService({
    String? apiUrl,
    OfflineLoginEventQueue? offlineLoginQueue,
    PendingAttendanceQueue? attendanceQueue,
  })  : _apiUrl = apiUrl ?? ApiConfig.baseUrl,
        _offlineLoginQueue = offlineLoginQueue ?? OfflineLoginEventQueue(),
        _attendanceQueue = attendanceQueue ?? PendingAttendanceQueue();

  /// Instancia compartida por toda la app (main, login, home).
  static final SyncService instance = SyncService();

  final String _apiUrl;
  final OfflineLoginEventQueue _offlineLoginQueue;
  final PendingAttendanceQueue _attendanceQueue;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;

  int get pendientes => _attendanceQueue.cantidadPendientes;

  void startListening() {
    debugPrint('SyncService: Iniciando y escuchando cambios de conexión...');

    // Intento al arrancar la app: `onConnectivityChanged` solo emite
    // cuando la conexión CAMBIA, asi que si el celular ya arranca con
    // señal nunca llegaria a dispararse por si solo.
    sincronizarTodo();

    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (_hayRed(results)) {
        debugPrint('SyncService: Conexión detectada. Intentando sincronizar...');
        sincronizarTodo();
      } else {
        debugPrint('SyncService: Sin conexión a internet.');
      }
    });
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  static bool _hayRed(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Vacia las dos colas pendientes. Nunca lanza.
  ///
  /// Devuelve el resultado de las asistencias, que es lo que la UI
  /// necesita para avisarle algo al trabajador.
  Future<PendingAttendanceSyncResult> sincronizarTodo() async {
    final resultado = await syncPendingAttendances();
    await syncPendingOfflineLoginEvents();
    return resultado;
  }

  /// CAV-83: al volver la conexión, reporta a Django los logins offline
  /// que quedaron pendientes en la cola local (CAV-81/82).
  Future<void> syncPendingOfflineLoginEvents() async {
    if (!_offlineLoginQueue.hayPendientes) return;

    final token = await _leerToken();
    if (token == null) return; // Sin sesión válida, no hay con qué reportar.

    try {
      await _offlineLoginQueue.flush(apiUrl: _apiUrl, token: token);
      debugPrint('SyncService: Eventos de login offline sincronizados.');
    } catch (e) {
      debugPrint('SyncService: No se pudo sincronizar login offline: $e');
    }
  }

  /// Sube a Django las marcaciones guardadas sin conexión.
  ///
  /// El candado `_isSyncing` se libera SIEMPRE (try/finally). Antes, si
  /// algo fallaba a media sincronización el candado quedaba trabado en
  /// `true` para toda la vida del proceso y ninguna asistencia volvia a
  /// sincronizarse hasta reinstalar la app: ese era el bug reportado.
  Future<PendingAttendanceSyncResult> syncPendingAttendances() async {
    if (_isSyncing) {
      debugPrint('SyncService: Sincronización ya en progreso. Omitiendo.');
      return PendingAttendanceSyncResult(
        estado: PendingAttendanceSyncStatus.completado,
        pendientes: _attendanceQueue.cantidadPendientes,
      );
    }

    if (!_attendanceQueue.hayPendientes) {
      return const PendingAttendanceSyncResult(
        estado: PendingAttendanceSyncStatus.sinPendientes,
      );
    }

    _isSyncing = true;
    try {
      debugPrint(
        'SyncService: ${_attendanceQueue.cantidadPendientes} asistencias '
        'pendientes. Enviando a Django...',
      );

      final token = await _leerToken();
      final resultado = await _attendanceQueue.flush(
        apiUrl: _apiUrl,
        token: token,
      );

      switch (resultado.estado) {
        case PendingAttendanceSyncStatus.completado:
          debugPrint(
            'SyncService: ${resultado.enviadas} asistencias sincronizadas, '
            '${resultado.rechazadas} rechazadas por el servidor.',
          );
        case PendingAttendanceSyncStatus.sinAutorizacion:
          debugPrint(
            'SyncService: token ausente o vencido. Quedan '
            '${resultado.pendientes} asistencias guardadas; se reintenta '
            'después del próximo inicio de sesión con internet.',
          );
        case PendingAttendanceSyncStatus.errorRed:
          debugPrint(
            'SyncService: falló la red. Quedan ${resultado.pendientes} '
            'asistencias guardadas para el próximo intento.',
          );
        case PendingAttendanceSyncStatus.sinPendientes:
          break;
      }

      return resultado;
    } catch (e, stack) {
      // Red de seguridad: pase lo que pase, el candado se libera en el
      // finally y la cola queda intacta para el siguiente intento.
      debugPrint('SyncService: error inesperado al sincronizar: $e\n$stack');
      return PendingAttendanceSyncResult(
        estado: PendingAttendanceSyncStatus.errorRed,
        pendientes: _attendanceQueue.cantidadPendientes,
      );
    } finally {
      _isSyncing = false;
      debugPrint('SyncService: Sincronización finalizada. Desbloqueando.');
    }
  }

  Future<String?> _leerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }
}

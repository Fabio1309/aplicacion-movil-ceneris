import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Resultado global de un intento de vaciado de la cola.
enum PendingAttendanceSyncStatus {
  /// No habia nada que enviar.
  sinPendientes,

  /// Se proceso toda la cola (aunque algun registro haya sido rechazado
  /// por el servidor y se haya quedado guardado para auditoria).
  completado,

  /// No hay token, esta vencido o el servidor lo rechazo (401/403).
  /// NO se borra nada: se reintenta despues del proximo login online.
  sinAutorizacion,

  /// Fallo de red o error del servidor (5xx). Se corta el envio y todo
  /// lo pendiente queda intacto para el siguiente intento.
  errorRed,
}

class PendingAttendanceSyncResult {
  const PendingAttendanceSyncResult({
    required this.estado,
    this.enviadas = 0,
    this.rechazadas = 0,
    this.pendientes = 0,
  });

  /// Como termino el intento completo.
  final PendingAttendanceSyncStatus estado;

  /// Registros confirmados por el backend y eliminados de la cola.
  final int enviadas;

  /// Registros que el backend rechazo con un error de cliente (4xx).
  /// NO se borran: quedan en la cola con el motivo, para revisarlos.
  final int rechazadas;

  /// Registros que siguen en la cola al terminar.
  final int pendientes;
}

/// CAV-83: cola local de marcaciones hechas sin conexion, pendientes de
/// registrar en Django (`POST /asistencias/registrar/`).
///
/// Reglas de oro de esta cola (una marcacion es un dato de planilla, no
/// se puede perder):
///
/// * Un registro SOLO se borra cuando el servidor confirma que lo
///   guardo (2xx) o avisa que ya lo tenia (409).
/// * Si falla la autenticacion (401/403) se corta el envio y no se
///   toca nada: el token se renueva recien en el proximo login online.
/// * Si falla la red o el servidor (5xx) se corta el envio y todo queda
///   pendiente.
/// * Si el servidor rechaza un registro puntual (4xx) se guarda el
///   motivo y se sigue con los demas; despues de [maxIntentos] se deja
///   de reintentar ese registro, pero tampoco se borra.
class PendingAttendanceQueue {
  PendingAttendanceQueue({http.Client? httpClient, Uuid? uuid})
      : _httpClient = httpClient ?? http.Client(),
        _uuid = uuid ?? const Uuid();

  static const boxName = 'asistencias_pendientes';

  /// Cuantas veces se reintenta un registro que el servidor rechaza con
  /// un 4xx antes de dejarlo quieto (sigue guardado para auditoria).
  static const maxIntentos = 5;

  /// Prefijo de los campos internos de la cola. Nunca se envian al
  /// backend: se quitan del payload antes del POST.
  static const _metaPrefix = '_';

  final http.Client _httpClient;
  final Uuid _uuid;

  Box get _box => Hive.box(boxName);

  bool get hayPendientes => _box.isNotEmpty;

  int get cantidadPendientes => _box.length;

  /// Guarda una marcacion hecha sin conexion. No requiere red.
  ///
  /// Se le agrega un `_local_id` propio del dispositivo para poder
  /// identificar el registro en logs sin depender de la clave de Hive.
  Future<void> enqueue(Map<String, dynamic> asistencia) async {
    await _box.add({
      ...asistencia,
      '_local_id': _uuid.v4(),
      '_intentos': 0,
    });
  }

  /// Copia de los registros pendientes (para mostrarlos en pantalla).
  List<Map<String, dynamic>> get pendientes => _box.keys
      .map((key) => Map<String, dynamic>.from(_box.get(key)))
      .toList();

  /// Payload real que se le manda a Django: el registro sin los campos
  /// internos de la cola.
  Map<String, dynamic> _payloadDe(Map<String, dynamic> registro) {
    return Map<String, dynamic>.from(registro)
      ..removeWhere((clave, _) => clave.startsWith(_metaPrefix));
  }

  /// Intenta registrar en Django todas las marcaciones pendientes.
  ///
  /// Nunca lanza: cualquier problema se refleja en el
  /// [PendingAttendanceSyncResult] devuelto.
  Future<PendingAttendanceSyncResult> flush({
    required String apiUrl,
    required String? token,
  }) async {
    if (_box.isEmpty) {
      return const PendingAttendanceSyncResult(
        estado: PendingAttendanceSyncStatus.sinPendientes,
      );
    }

    // Sin token no tiene sentido intentar: el backend responderia 401 y
    // antes esto terminaba borrando la marcacion igual (bug CAV-83).
    // Pasa siempre que la sesion se abrio en modo offline.
    if (token == null || token.isEmpty) {
      return PendingAttendanceSyncResult(
        estado: PendingAttendanceSyncStatus.sinAutorizacion,
        pendientes: _box.length,
      );
    }

    final uri = Uri.parse('$apiUrl/asistencias/registrar/');
    final clavesConfirmadas = <dynamic>[];
    var rechazadas = 0;

    for (final key in _box.keys.toList()) {
      final registro = Map<String, dynamic>.from(_box.get(key));

      // Registro que el servidor ya rechazo demasiadas veces: no se
      // reintenta mas, pero se conserva para que RR.HH. lo revise.
      final intentos = (registro['_intentos'] as num?)?.toInt() ?? 0;
      if (intentos >= maxIntentos) {
        rechazadas++;
        continue;
      }

      http.Response response;
      try {
        response = await _httpClient
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json; charset=UTF-8',
                'Authorization': 'Bearer $token',
              },
              body: json.encode(_payloadDe(registro)),
            )
            .timeout(const Duration(seconds: 45));
      } catch (_) {
        // Sin conexion o servidor caido: se corta aca y todo lo que
        // queda sigue pendiente para el proximo intento.
        return _resultadoParcial(
          PendingAttendanceSyncStatus.errorRed,
          clavesConfirmadas,
          rechazadas,
        );
      }

      final status = response.statusCode;

      // El 409 se toma como "el backend ya tenia esta marcacion", asi
      // que cuenta como sincronizada y sale de la cola.
      if ((status >= 200 && status < 300) || status == 409) {
        clavesConfirmadas.add(key);
        continue;
      }

      if (status == 401 || status == 403) {
        // Token vencido o sesion abierta offline: se conserva TODO y se
        // reintenta cuando haya un login online que renueve el token.
        return _resultadoParcial(
          PendingAttendanceSyncStatus.sinAutorizacion,
          clavesConfirmadas,
          rechazadas,
        );
      }

      if (status >= 500) {
        // Problema del servidor, no del registro: se corta el envio.
        return _resultadoParcial(
          PendingAttendanceSyncStatus.errorRed,
          clavesConfirmadas,
          rechazadas,
        );
      }

      // 4xx puntual (datos invalidos, etc.): es problema de ESTE
      // registro, asi que se anota el motivo y se sigue con los demas
      // en vez de bloquear toda la cola.
      rechazadas++;
      await _box.put(key, {
        ...registro,
        '_intentos': intentos + 1,
        '_ultimo_error': 'HTTP $status: ${response.body}',
      });
    }

    return _resultadoParcial(
      PendingAttendanceSyncStatus.completado,
      clavesConfirmadas,
      rechazadas,
    );
  }

  /// Borra lo confirmado hasta el momento y arma el resultado. Se llama
  /// tambien cuando el envio se corta a la mitad, para no perder el
  /// avance de los registros que el servidor si acepto.
  Future<PendingAttendanceSyncResult> _resultadoParcial(
    PendingAttendanceSyncStatus estado,
    List<dynamic> clavesConfirmadas,
    int rechazadas,
  ) async {
    if (clavesConfirmadas.isNotEmpty) {
      await _box.deleteAll(clavesConfirmadas);
    }
    return PendingAttendanceSyncResult(
      estado: estado,
      enviadas: clavesConfirmadas.length,
      rechazadas: rechazadas,
      pendientes: _box.length,
    );
  }
}

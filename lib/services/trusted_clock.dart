import 'dart:convert';

import 'package:http/http.dart' as http;

import 'device_clock.dart';
import 'secure_store.dart';

/// De dónde salió la hora con la que se registra una marcación.
enum FuenteHora {
  /// Hora del servidor proyectada con el reloj monotónico del equipo.
  /// Es la buena: no se puede falsear cambiando la hora del celular.
  servidorMonotonico,

  /// Hora del fix de GPS (viene de los satélites). Respaldo cuando el
  /// ancla del servidor ya no sirve (por ejemplo, tras reiniciar el
  /// equipo estando sin señal).
  gps,

  /// Último recurso: el reloj del propio celular. NO es confiable.
  dispositivo,
}

extension FuenteHoraCodigo on FuenteHora {
  String get codigo => switch (this) {
        FuenteHora.servidorMonotonico => 'servidor_monotonico',
        FuenteHora.gps => 'gps',
        FuenteHora.dispositivo => 'dispositivo',
      };
}

/// Hora calculada para una marcación, junto con la evidencia que
/// permite auditarla después.
class HoraConfiable {
  const HoraConfiable({
    required this.utc,
    required this.horaDispositivo,
    required this.fuente,
    required this.desfaseReloj,
    required this.relojManipulado,
    required this.zonaHorariaCambiada,
    this.horaAutomaticaActiva,
    this.antiguedadAncla,
  });

  /// Mejor estimación de la hora real, en UTC.
  final DateTime utc;

  /// Lo que marcaba el reloj del celular en ese mismo instante.
  final DateTime horaDispositivo;

  final FuenteHora fuente;

  /// `horaDispositivo - utc`. Negativo = el celular va atrasado
  /// (el caso típico del que atrasa el reloj para "llegar temprano").
  final Duration desfaseReloj;

  /// El desfase supera la tolerancia y la hora real es de una fuente
  /// confiable: hay evidencia de reloj alterado.
  final bool relojManipulado;

  /// Cambió la zona horaria del equipo desde el último anclaje (otra
  /// forma de correr la hora sin tocar el reloj).
  final bool zonaHorariaCambiada;

  /// Solo Android: si la fecha/hora automática está activa.
  final bool? horaAutomaticaActiva;

  /// Hace cuánto se ancló contra el servidor. Mientras más viejo, más
  /// deriva acumulada puede tener el cálculo (unos segundos por día).
  final Duration? antiguedadAncla;

  /// La hora se obtuvo de una fuente que el trabajador no controla.
  bool get esConfiable => fuente != FuenteHora.dispositivo;

  /// Hora local del equipo derivada de [utc]. Se conserva por
  /// compatibilidad con lo que hoy espera el backend.
  DateTime get local => utc.toLocal();

  /// Campos que viajan al backend junto con la marcación para que
  /// RR.HH. pueda auditar cualquier registro sospechoso.
  Map<String, dynamic> comoEvidencia() => {
        'timestamp_utc': utc.toIso8601String(),
        'timestamp_dispositivo': horaDispositivo.toIso8601String(),
        'fuente_hora': fuente.codigo,
        'hora_confiable': esConfiable,
        'desfase_reloj_segundos': desfaseReloj.inSeconds,
        'reloj_manipulado': relojManipulado,
        'zona_horaria_cambiada': zonaHorariaCambiada,
        'zona_horaria_offset_minutos': horaDispositivo.timeZoneOffset.inMinutes,
        if (horaAutomaticaActiva != null)
          'hora_automatica_activa': horaAutomaticaActiva,
        if (antiguedadAncla != null)
          'antiguedad_ancla_horas': antiguedadAncla!.inHours,
      };
}

/// CAV-83 (antifraude de reloj): calcula la hora real de una marcación
/// hecha SIN conexión, sin confiar en el reloj del celular.
///
/// ## Cómo funciona
///
/// Cada vez que la app habla con el servidor se guarda un "ancla":
/// la hora del servidor (cabecera HTTP `Date`) junto al valor del reloj
/// monotónico del equipo en ese mismo instante ([DeviceClock]).
///
/// Después, ya sin conexión:
///
///     hora_real = hora_servidor_del_ancla + (monotónico_ahora - monotónico_del_ancla)
///
/// El reloj monotónico cuenta desde el arranque del equipo y no se puede
/// cambiar desde Ajustes, así que atrasar la hora del celular no mueve
/// este cálculo. Si el trabajador pone su celular en 8:25 cuando en
/// realidad son 8:50, la marcación se guarda con 8:50 y además viaja la
/// evidencia (`reloj_manipulado: true`, `desfase_reloj_segundos: -1500`).
///
/// ## Qué pasa si reinician el equipo
///
/// Al reiniciar, el reloj monotónico vuelve a cero y el ancla deja de
/// servir. Se detecta (el monotónico "retrocede") y se descarta el ancla.
/// A partir de ahí se usa la hora del fix de GPS, que viene de los
/// satélites, y si tampoco hay, se cae al reloj del celular pero el
/// registro queda marcado como `hora_confiable: false` para que RR.HH.
/// lo revise. Nunca se descarta la marcación en silencio.
class TrustedClock {
  TrustedClock({
    SecureStore? store,
    DeviceClock deviceClock = const DeviceClock(),
    DateTime Function()? ahoraDispositivo,
  })  : _store = store ?? FlutterSecureCredentialStorage(),
        _deviceClock = deviceClock,
        _ahoraDispositivo = ahoraDispositivo ?? DateTime.now;

  /// Instancia compartida por la app.
  static final TrustedClock instance = TrustedClock();

  /// Desfase a partir del cual se considera que el reloj fue alterado.
  /// Dos minutos deja pasar la deriva normal de un celular sin hora
  /// automática, pero no un cambio hecho a propósito.
  static const toleranciaDesfase = Duration(minutes: 2);

  static const _anclaKey = 'reloj_ancla_servidor';
  static const _ultimoElapsedKey = 'reloj_ultimo_elapsed_ms';

  final SecureStore _store;
  final DeviceClock _deviceClock;
  final DateTime Function() _ahoraDispositivo;

  static const _meses = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  static final _formatoFechaHttp = RegExp(
    r'^\w{3},\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$',
  );

  /// Parsea la cabecera HTTP `Date` (formato IMF-fixdate, el que manda
  /// cualquier servidor HTTP). Devuelve `null` si no se puede leer.
  static DateTime? parsearFechaHttp(String? raw) {
    if (raw == null) return null;
    final match = _formatoFechaHttp.firstMatch(raw.trim());
    if (match == null) return null;
    final mes = _meses[match.group(2)];
    if (mes == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      mes,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  /// Ancla usando la hora del servidor que viaja en cualquier respuesta
  /// HTTP. No requiere ningún cambio en el backend.
  Future<void> anclarConRespuesta(http.BaseResponse response) async {
    final horaServidor = parsearFechaHttp(response.headers['date']);
    if (horaServidor == null) return;
    await anclarConHoraServidor(horaServidor);
  }

  /// Guarda la hora del servidor junto al valor actual del reloj
  /// monotónico. Si la plataforma no expone el monotónico no se ancla:
  /// es preferible no tener ancla a tener una que no sirve.
  Future<void> anclarConHoraServidor(DateTime horaServidor) async {
    final elapsed = await _deviceClock.elapsedRealtime();
    if (elapsed == null) return;

    final dispositivo = _ahoraDispositivo();
    await _store.write(
      key: _anclaKey,
      value: jsonEncode({
        'servidor_utc': horaServidor.toUtc().toIso8601String(),
        'elapsed_ms': elapsed.inMilliseconds,
        'dispositivo_utc': dispositivo.toUtc().toIso8601String(),
        'offset_tz_min': dispositivo.timeZoneOffset.inMinutes,
        'boot_count': await _deviceClock.bootCount(),
      }),
    );
    await _registrarElapsed(elapsed);
  }

  /// ¿Hay un ancla utilizable en este momento?
  Future<bool> get tieneAnclaValida async {
    final ancla = await _leerAncla();
    if (ancla == null) return false;
    final elapsed = await _deviceClock.elapsedRealtime();
    return elapsed != null && !await _huboReinicio(elapsed, ancla);
  }

  /// Calcula la hora real del momento actual.
  ///
  /// [horaGps] es el `timestamp` del fix de GPS (geolocator ya lo
  /// entrega en cada marcación) y se usa como respaldo si el ancla no
  /// sirve.
  Future<HoraConfiable> ahora({DateTime? horaGps}) async {
    final dispositivo = _ahoraDispositivo();
    final elapsed = await _deviceClock.elapsedRealtime();
    final ancla = await _leerAncla();

    DateTime utc;
    FuenteHora fuente;
    Duration? antiguedadAncla;

    if (ancla != null && elapsed != null && !await _huboReinicio(elapsed, ancla)) {
      final transcurrido = Duration(
        milliseconds: elapsed.inMilliseconds - ancla.elapsedMs,
      );
      utc = ancla.servidorUtc.add(transcurrido);
      fuente = FuenteHora.servidorMonotonico;
      antiguedadAncla = transcurrido;
    } else if (horaGps != null) {
      utc = horaGps.toUtc();
      fuente = FuenteHora.gps;
    } else {
      utc = dispositivo.toUtc();
      fuente = FuenteHora.dispositivo;
    }

    if (elapsed != null) {
      await _registrarElapsed(elapsed);
    }

    final desfase = dispositivo.toUtc().difference(utc);
    final esConfiable = fuente != FuenteHora.dispositivo;

    return HoraConfiable(
      utc: utc,
      horaDispositivo: dispositivo,
      fuente: fuente,
      desfaseReloj: desfase,
      relojManipulado: esConfiable && desfase.abs() > toleranciaDesfase,
      zonaHorariaCambiada: ancla != null &&
          ancla.offsetTzMin != dispositivo.timeZoneOffset.inMinutes,
      horaAutomaticaActiva: await _deviceClock.horaAutomaticaActiva(),
      antiguedadAncla: antiguedadAncla,
    );
  }

  /// Detecta que el equipo se reinició, que es lo único que invalida el
  /// ancla (el reloj monotónico vuelve a cero). Tres señales, de la más
  /// fuerte a la más débil:
  ///
  /// 1. cambió el contador de arranques del sistema (Android 7+): es
  ///    prueba directa de reinicio y no depende de heurísticas;
  /// 2. el monotónico actual es menor que el del ancla;
  /// 3. el monotónico actual es menor que el valor más alto observado
  ///    (se registra en cada consulta, no solo cuando hay red).
  ///
  /// Detectado un reinicio, el ancla se borra: es preferible caer al
  /// GPS y marcar el registro como no confiable, antes que proyectar
  /// una hora inventada.
  Future<bool> _huboReinicio(Duration elapsed, _Ancla ancla) async {
    final bootCount = await _deviceClock.bootCount();
    if (bootCount != null && ancla.bootCount != null) {
      if (bootCount != ancla.bootCount) {
        await _invalidarAncla(elapsed);
        return true;
      }
      // El contador de arranques coincide: no hubo reinicio, punto.
      return false;
    }

    if (elapsed.inMilliseconds < ancla.elapsedMs) {
      await _invalidarAncla(elapsed);
      return true;
    }

    final ultimo = await _leerUltimoElapsed();
    if (ultimo != null && elapsed.inMilliseconds < ultimo) {
      await _invalidarAncla(elapsed);
      return true;
    }

    return false;
  }

  Future<void> _invalidarAncla(Duration elapsed) async {
    await _store.delete(key: _anclaKey);
    // El máximo observado pertenecía al arranque anterior: si no se
    // reinicia también, el próximo ancla nacería ya "vencido".
    await _registrarElapsed(elapsed);
  }

  /// El monotónico nunca retrocede dentro de un mismo arranque, así que
  /// el valor actual siempre es el máximo observado en esta sesión.
  Future<void> _registrarElapsed(Duration elapsed) {
    return _store.write(
      key: _ultimoElapsedKey,
      value: elapsed.inMilliseconds.toString(),
    );
  }

  Future<int?> _leerUltimoElapsed() async {
    final raw = await _store.read(key: _ultimoElapsedKey);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<_Ancla?> _leerAncla() async {
    final raw = await _store.read(key: _anclaKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return _Ancla(
        servidorUtc: DateTime.parse(data['servidor_utc'] as String),
        elapsedMs: (data['elapsed_ms'] as num).toInt(),
        offsetTzMin: (data['offset_tz_min'] as num?)?.toInt() ?? 0,
        bootCount: (data['boot_count'] as num?)?.toInt(),
      );
    } catch (_) {
      // Ancla corrupta o manipulada: se descarta.
      return null;
    }
  }
}

class _Ancla {
  const _Ancla({
    required this.servidorUtc,
    required this.elapsedMs,
    required this.offsetTzMin,
    this.bootCount,
  });

  final DateTime servidorUtc;
  final int elapsedMs;
  final int offsetTzMin;
  final int? bootCount;
}

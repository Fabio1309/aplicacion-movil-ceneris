import 'package:ceneris/services/device_clock.dart';
import 'package:ceneris/services/trusted_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'secure_credential_store_test.dart' show FakeSecureStore;

/// Reloj monotónico simulado: representa el tiempo desde el arranque,
/// que en el equipo real no se puede modificar desde Ajustes.
class _FakeDeviceClock extends DeviceClock {
  _FakeDeviceClock({required this.elapsed, this.boot});

  Duration? elapsed;
  int? boot;

  @override
  Future<Duration?> elapsedRealtime() async => elapsed;

  @override
  Future<int?> bootCount() async => boot;

  @override
  Future<bool?> horaAutomaticaActiva() async => false;
}

void main() {
  group('TrustedClock (antifraude de reloj)', () {
    late FakeSecureStore store;
    late _FakeDeviceClock deviceClock;

    /// Hora "real" del servidor al momento de anclar.
    final horaServidor = DateTime.utc(2026, 8, 20, 13, 0, 0);

    /// Lo que marca el reloj del celular. Es el valor que el trabajador
    /// puede alterar a voluntad.
    late DateTime relojCelular;

    TrustedClock construir() => TrustedClock(
          store: store,
          deviceClock: deviceClock,
          ahoraDispositivo: () => relojCelular,
        );

    setUp(() {
      store = FakeSecureStore();
      deviceClock = _FakeDeviceClock(elapsed: const Duration(hours: 5), boot: 7);
      relojCelular = horaServidor.toLocal();
    });

    test('lee la hora del servidor de la cabecera HTTP Date', () {
      final parseada =
          TrustedClock.parsearFechaHttp('Thu, 20 Aug 2026 13:00:00 GMT');

      expect(parseada, DateTime.utc(2026, 8, 20, 13, 0, 0));
    });

    test('ignora una cabecera Date ilegible', () {
      expect(TrustedClock.parsearFechaHttp(null), isNull);
      expect(TrustedClock.parsearFechaHttp('cualquier cosa'), isNull);
    });

    test('ancla desde una respuesta HTTP real', () async {
      final reloj = construir();
      final respuesta = http.Response('{}', 200,
          headers: {'date': 'Thu, 20 Aug 2026 13:00:00 GMT'});

      await reloj.anclarConRespuesta(respuesta);

      expect(await reloj.tieneAnclaValida, isTrue);
    });

    test('EL CASO DEL FRAUDE: el trabajador atrasa el reloj del celular '
        '25 minutos y aun así se registra la hora real', () async {
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor); // 13:00 UTC, uptime 5h

      // Pasan 50 minutos reales (el monotónico no se puede tocar)...
      deviceClock.elapsed = const Duration(hours: 5, minutes: 50);
      // ...pero el trabajador pone su celular 25 minutos atrás.
      relojCelular =
          horaServidor.add(const Duration(minutes: 25)).toLocal();

      final hora = await reloj.ahora();

      expect(hora.fuente, FuenteHora.servidorMonotonico);
      expect(hora.utc, DateTime.utc(2026, 8, 20, 13, 50, 0),
          reason: 'la hora real, no la del celular');
      expect(hora.relojManipulado, isTrue);
      expect(hora.desfaseReloj.inMinutes, -25,
          reason: 'el celular va 25 minutos atrasado');
      expect(hora.esConfiable, isTrue);
    });

    test('un desfase pequeño (deriva normal) no se marca como fraude',
        () async {
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor);

      deviceClock.elapsed = const Duration(hours: 6);
      relojCelular =
          horaServidor.add(const Duration(hours: 1, seconds: 30)).toLocal();

      final hora = await reloj.ahora();

      expect(hora.relojManipulado, isFalse);
      expect(hora.fuente, FuenteHora.servidorMonotonico);
    });

    test('adelantar el reloj del celular tampoco funciona', () async {
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor);

      deviceClock.elapsed = const Duration(hours: 5, minutes: 10);
      relojCelular = horaServidor.add(const Duration(hours: 3)).toLocal();

      final hora = await reloj.ahora();

      expect(hora.utc, DateTime.utc(2026, 8, 20, 13, 10, 0));
      expect(hora.relojManipulado, isTrue);
      expect(hora.desfaseReloj.inMinutes, 170);
    });

    test('si reinician el equipo, el ancla se descarta y se usa el GPS',
        () async {
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor);

      // Reinicio: cambia el contador de arranques y el monotónico
      // vuelve a valores bajos.
      deviceClock.boot = 8;
      deviceClock.elapsed = const Duration(minutes: 3);
      relojCelular = horaServidor.subtract(const Duration(hours: 2)).toLocal();

      final horaGps = DateTime.utc(2026, 8, 20, 14, 30, 0);
      final hora = await reloj.ahora(horaGps: horaGps);

      expect(hora.fuente, FuenteHora.gps);
      expect(hora.utc, horaGps);
      expect(hora.relojManipulado, isTrue, reason: 'el celular va 4h30 atrás');
      expect(await reloj.tieneAnclaValida, isFalse);
    });

    test('reinicio detectado por el monotónico cuando no hay contador de '
        'arranques (iOS)', () async {
      deviceClock.boot = null;
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor);

      deviceClock.elapsed = const Duration(minutes: 2); // retrocedió

      final hora = await reloj.ahora();

      expect(hora.fuente, FuenteHora.dispositivo);
      expect(await reloj.tieneAnclaValida, isFalse);
    });

    test('tras un reinicio se puede volver a anclar de inmediato', () async {
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor); // uptime 5h

      // Reinicio + reconexión: el ancla nueva nace con un uptime bajo y
      // no debe confundirse con el máximo observado antes del reinicio.
      deviceClock.boot = 8;
      deviceClock.elapsed = const Duration(minutes: 1);
      await reloj.ahora(); // detecta el reinicio

      final nuevaHora = DateTime.utc(2026, 8, 20, 20, 0, 0);
      await reloj.anclarConHoraServidor(nuevaHora);

      deviceClock.elapsed = const Duration(minutes: 31);
      final hora = await reloj.ahora();

      expect(hora.fuente, FuenteHora.servidorMonotonico);
      expect(hora.utc, DateTime.utc(2026, 8, 20, 20, 30, 0));
    });

    test('sin ancla y sin GPS, la hora es la del celular pero se marca '
        'como NO confiable', () async {
      final reloj = construir();

      final hora = await reloj.ahora();

      expect(hora.fuente, FuenteHora.dispositivo);
      expect(hora.esConfiable, isFalse);
      expect(hora.relojManipulado, isFalse,
          reason: 'no hay contra qué comparar; el backend decide');
    });

    test('no ancla si la plataforma no expone el reloj monotónico',
        () async {
      deviceClock.elapsed = null;
      final reloj = construir();

      await reloj.anclarConHoraServidor(horaServidor);

      expect(await reloj.tieneAnclaValida, isFalse);
    });

    test('la evidencia que viaja al backend incluye el desfase y la fuente',
        () async {
      final reloj = construir();
      await reloj.anclarConHoraServidor(horaServidor);

      deviceClock.elapsed = const Duration(hours: 5, minutes: 30);
      relojCelular = horaServidor.subtract(const Duration(minutes: 10)).toLocal();

      final evidencia = (await reloj.ahora()).comoEvidencia();

      expect(evidencia['fuente_hora'], 'servidor_monotonico');
      expect(evidencia['hora_confiable'], isTrue);
      expect(evidencia['reloj_manipulado'], isTrue);
      expect(evidencia['desfase_reloj_segundos'], -2400);
      expect(evidencia['timestamp_utc'], '2026-08-20T13:30:00.000Z');
      expect(evidencia['hora_automatica_activa'], isFalse);
    });
  });
}

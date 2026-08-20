import 'dart:convert';
import 'dart:io';

import 'package:ceneris/services/pending_attendance_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Marcación tal cual la guarda `home_screen.dart` cuando no hay señal.
Map<String, dynamic> _marcacion({String tipo = 'Entrada'}) => {
      'tipo_marcacion': tipo,
      'latitud': -12.0464,
      'longitud': -77.0428,
      'device_id': 'device-1',
      'nombre_ubicacion': 'Offline',
      'timestamp': DateTime.now().toIso8601String(),
    };

void main() {
  group('PendingAttendanceQueue (CAV-83)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_asistencias_');
      Hive.init(tempDir.path);
      await Hive.openBox(PendingAttendanceQueue.boxName);
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk(PendingAttendanceQueue.boxName);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('encola una marcación sin necesitar conexión', () async {
      final queue = PendingAttendanceQueue();

      expect(queue.hayPendientes, isFalse);
      await queue.enqueue(_marcacion());

      expect(queue.hayPendientes, isTrue);
      expect(queue.cantidadPendientes, 1);
    });

    test('envía las pendientes y las borra cuando el servidor responde 201',
        () async {
      var requests = 0;

      final mockClient = MockClient((request) async {
        requests++;
        expect(request.url.path, contains('/asistencias/registrar/'));
        expect(request.headers['Authorization'], 'Bearer token-valido');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['tipo_marcacion'], isNotNull);
        expect(body['device_id'], 'device-1');
        // Los campos internos de la cola no deben viajar al backend.
        expect(body.keys.where((k) => k.startsWith('_')), isEmpty);

        return http.Response('{"mensaje":"ok"}', 201);
      });

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion(tipo: 'Entrada'));
      await queue.enqueue(_marcacion(tipo: 'Salida'));

      final resultado = await queue.flush(
        apiUrl: 'https://api.test/api',
        token: 'token-valido',
      );

      expect(requests, 2);
      expect(resultado.estado, PendingAttendanceSyncStatus.completado);
      expect(resultado.enviadas, 2);
      expect(queue.hayPendientes, isFalse);
    });

    test('NO borra la marcación si el servidor responde 401 (token vencido '
        'o sesión abierta sin conexión)', () async {
      final mockClient = MockClient(
        (_) async => http.Response('{"detail":"token no válido"}', 401),
      );

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion());

      final resultado = await queue.flush(
        apiUrl: 'https://api.test/api',
        token: 'token-vencido',
      );

      expect(resultado.estado, PendingAttendanceSyncStatus.sinAutorizacion);
      expect(resultado.enviadas, 0);
      expect(queue.cantidadPendientes, 1,
          reason: 'una marcación de planilla no se puede perder por un 401');
    });

    test('sin token no intenta enviar y conserva todo', () async {
      var requests = 0;
      final mockClient = MockClient((_) async {
        requests++;
        return http.Response('', 201);
      });

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion());

      final resultado =
          await queue.flush(apiUrl: 'https://api.test/api', token: null);

      expect(requests, 0);
      expect(resultado.estado, PendingAttendanceSyncStatus.sinAutorizacion);
      expect(queue.cantidadPendientes, 1);
    });

    test('conserva lo pendiente cuando falla la red, sin perder lo ya '
        'confirmado', () async {
      var requests = 0;
      final mockClient = MockClient((_) async {
        requests++;
        if (requests == 1) return http.Response('{}', 201);
        throw const SocketException('sin conexión');
      });

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion(tipo: 'Entrada'));
      await queue.enqueue(_marcacion(tipo: 'Salida'));

      final resultado = await queue.flush(
        apiUrl: 'https://api.test/api',
        token: 'token-valido',
      );

      expect(resultado.estado, PendingAttendanceSyncStatus.errorRed);
      expect(resultado.enviadas, 1);
      expect(queue.cantidadPendientes, 1);
    });

    test('un 400 puntual no bloquea al resto de la cola', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['tipo_marcacion'] == 'Entrada') {
          return http.Response('{"detail":"fecha inválida"}', 400);
        }
        return http.Response('{}', 201);
      });

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion(tipo: 'Entrada'));
      await queue.enqueue(_marcacion(tipo: 'Salida'));

      final resultado = await queue.flush(
        apiUrl: 'https://api.test/api',
        token: 'token-valido',
      );

      expect(resultado.estado, PendingAttendanceSyncStatus.completado);
      expect(resultado.enviadas, 1);
      expect(resultado.rechazadas, 1);
      expect(queue.cantidadPendientes, 1);
      expect(queue.pendientes.single['_ultimo_error'], contains('HTTP 400'));
    });

    test('deja de reintentar un registro rechazado tras maxIntentos',
        () async {
      var requests = 0;
      final mockClient = MockClient((_) async {
        requests++;
        return http.Response('{"detail":"inválido"}', 400);
      });

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion());

      for (var i = 0; i < PendingAttendanceQueue.maxIntentos + 3; i++) {
        await queue.flush(apiUrl: 'https://api.test/api', token: 'token');
      }

      expect(requests, PendingAttendanceQueue.maxIntentos);
      expect(queue.cantidadPendientes, 1,
          reason: 'se conserva para auditoría, nunca se borra en silencio');
    });

    test('el 409 (ya registrada en el backend) saca la marcación de la cola',
        () async {
      final mockClient = MockClient(
        (_) async => http.Response('{"detail":"duplicada"}', 409),
      );

      final queue = PendingAttendanceQueue(httpClient: mockClient);
      await queue.enqueue(_marcacion());

      final resultado = await queue.flush(
        apiUrl: 'https://api.test/api',
        token: 'token',
      );

      expect(resultado.enviadas, 1);
      expect(queue.hayPendientes, isFalse);
    });
  });
}

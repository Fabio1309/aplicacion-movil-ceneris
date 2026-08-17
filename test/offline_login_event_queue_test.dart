import 'dart:convert';
import 'dart:io';

import 'package:ceneris/services/offline_login_event_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('OfflineLoginEventQueue (CAV-83)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(OfflineLoginEventQueue.boxName);
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk(OfflineLoginEventQueue.boxName);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('encola un evento sin necesitar conexión', () async {
      final queue = OfflineLoginEventQueue();

      expect(queue.hayPendientes, isFalse);

      await queue.enqueue(
        deviceId: 'device-1',
        fechaHoraOffline: DateTime.now(),
      );

      expect(queue.hayPendientes, isTrue);
    });

    test('flush envia los eventos pendientes y los elimina de la cola '
        'si el servidor responde 201', () async {
      var requestsRecibidas = 0;

      final mockClient = MockClient((request) async {
        requestsRecibidas++;
        expect(request.url.path, contains('/eventos/login-offline/'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_id'], isNotNull);
        expect(body['fecha_hora_offline'], isNotNull);
        return http.Response('{"mensaje":"ok","id":1}', 201);
      });

      final queue = OfflineLoginEventQueue(httpClient: mockClient);
      await queue.enqueue(
        deviceId: 'device-1',
        fechaHoraOffline: DateTime.now(),
      );
      await queue.enqueue(
        deviceId: 'device-1',
        fechaHoraOffline: DateTime.now(),
      );

      await queue.flush(apiUrl: 'http://127.0.0.1:8001/api', token: 'tok');

      expect(requestsRecibidas, 2);
      expect(queue.hayPendientes, isFalse);
    });

    test('si el servidor falla, el evento se mantiene en la cola', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error":"server error"}', 500);
      });

      final queue = OfflineLoginEventQueue(httpClient: mockClient);
      await queue.enqueue(
        deviceId: 'device-1',
        fechaHoraOffline: DateTime.now(),
      );

      await queue.flush(apiUrl: 'http://127.0.0.1:8001/api', token: 'tok');

      expect(queue.hayPendientes, isTrue);
    });

    test('si no hay conexión (excepción de red), el evento no se pierde',
        () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('sin conexión');
      });

      final queue = OfflineLoginEventQueue(httpClient: mockClient);
      await queue.enqueue(
        deviceId: 'device-1',
        fechaHoraOffline: DateTime.now(),
      );

      await queue.flush(apiUrl: 'http://127.0.0.1:8001/api', token: 'tok');

      expect(queue.hayPendientes, isTrue);
    });

    test('flush sin nada pendiente no hace ninguna llamada de red', () async {
      var seLlamo = false;
      final mockClient = MockClient((request) async {
        seLlamo = true;
        return http.Response('{}', 201);
      });

      final queue = OfflineLoginEventQueue(httpClient: mockClient);
      await queue.flush(apiUrl: 'http://127.0.0.1:8001/api', token: 'tok');

      expect(seLlamo, isFalse);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:ceneris/services/auth_token_provider.dart';
import 'package:ceneris/services/network_status.dart';
import 'package:ceneris/services/offline_login_event_queue.dart';
import 'package:ceneris/services/secure_store.dart';
import 'package:ceneris/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implementacion en memoria de [SecureStore] para tests: evita depender del
/// canal de plataforma real de flutter_secure_storage.
class FakeSecureStore implements SecureStore {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _data[key];

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }
}

Map<String, dynamic> _marcaOffline({String tipo = 'Entrada'}) => {
      'tipo_marcacion': tipo,
      'latitud': -12.0464,
      'longitud': -77.0428,
      'device_id': 'device-1',
      'nombre_ubicacion': 'Offline',
      'timestamp': DateTime.now().toIso8601String(),
      'intentos': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncService: cola offline de asistencias', () {
    late Directory tempDir;
    late Box pendingBox;
    late FakeSecureStore secureStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_sync_test_');
      Hive.init(tempDir.path);
      pendingBox = await Hive.openBox(SyncService.pendingBoxName);
      await Hive.openBox(SyncService.rejectedBoxName);
      await Hive.openBox(OfflineLoginEventQueue.boxName);

      SharedPreferences.setMockInitialValues({'authToken': 'token-viejo'});
      secureStore = FakeSecureStore();
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk(SyncService.pendingBoxName);
      await Hive.deleteBoxFromDisk(SyncService.rejectedBoxName);
      await Hive.deleteBoxFromDisk(OfflineLoginEventQueue.boxName);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// Construye un worker aislado: cliente HTTP simulado, sonda de red
    /// controlada y sin escuchar conectividad real.
    SyncService buildService({
      required MockClient attendanceClient,
      http.Client? refreshClient,
      Future<bool> Function()? probe,
    }) {
      final service = SyncService(
        apiUrl: 'http://127.0.0.1:8001/api',
        httpClient: attendanceClient,
        authTokenProvider: AuthTokenProvider(
          apiUrl: 'http://127.0.0.1:8001/api',
          httpClient: refreshClient ??
              MockClient((_) async => http.Response('{}', 401)),
          store: secureStore,
        ),
        connectivityProbe: probe ?? () async => true,
        connectivityRestored: const Stream<void>.empty(),
        baseBackoff: const Duration(milliseconds: 5),
      );
      addTearDown(service.dispose);
      return service;
    }

    test('envia la marca con el esquema real y la borra al recibir 201',
        () async {
      Map<String, dynamic>? enviado;
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/asistencias/registrar/'));
        expect(request.headers['authorization'], 'Bearer token-viejo');
        enviado = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"id":1}', 201);
      });

      await pendingBox.add(_marcaOffline());
      await buildService(attendanceClient: client).syncPendingAttendances();

      expect(pendingBox.isEmpty, isTrue);
      expect(enviado!['tipo_marcacion'], 'Entrada');
      expect(enviado!['latitud'], -12.0464);
      // Los campos de control son locales y no deben viajar al backend.
      expect(enviado!.containsKey('intentos'), isFalse);
    });

    test('un fallo inesperado no deja el worker trabado (regresion del '
        'deadlock de _isSyncing)', () async {
      var intentos = 0;
      final client = MockClient((_) async => http.Response('{"id":1}', 201));

      final service = buildService(
        attendanceClient: client,
        probe: () async {
          intentos++;
          // El primer ciclo revienta a mitad de camino.
          if (intentos == 1) throw StateError('fallo simulado');
          return true;
        },
      );

      await pendingBox.add(_marcaOffline());

      await service.syncPendingAttendances();
      expect(pendingBox.length, 1, reason: 'el primer ciclo falla');

      // Antes del fix, `_isSyncing` quedaba en true para siempre y esta
      // segunda llamada salia por "sincronizacion ya en progreso".
      await service.syncPendingAttendances();
      expect(pendingBox.isEmpty, isTrue);
      expect(intentos, 2);
    });

    test('ante 401 renueva el token y reintenta la misma marca', () async {
      await secureStore.write(
        key: AuthTokenProvider.refreshTokenKey,
        value: 'refresh-valido',
      );

      final tokensUsados = <String>[];
      final client = MockClient((request) async {
        final token = request.headers['authorization'];
        tokensUsados.add(token ?? '');
        if (token == 'Bearer token-nuevo') {
          return http.Response('{"id":1}', 201);
        }
        return http.Response('{"detail":"token expirado"}', 401);
      });

      final refreshClient = MockClient((request) async {
        expect(request.url.path, endsWith('/token/refresh/'));
        expect(jsonDecode(request.body)['refresh'], 'refresh-valido');
        return http.Response('{"access":"token-nuevo"}', 200);
      });

      await pendingBox.add(_marcaOffline());
      await buildService(
        attendanceClient: client,
        refreshClient: refreshClient,
      ).syncPendingAttendances();

      expect(pendingBox.isEmpty, isTrue);
      expect(tokensUsados, ['Bearer token-viejo', 'Bearer token-nuevo']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('authToken'), 'token-nuevo');
    });

    test('si el refresh falla, la marca NO se pierde', () async {
      // Sin refresh guardado: es el escenario del token caducado mientras el
      // trabajador estuvo sin conexion. Antes, el codigo borraba el registro
      // sin mirar el statusCode y la marcacion se destruia en silencio.
      final client = MockClient(
        (_) async => http.Response('{"detail":"token expirado"}', 401),
      );

      await pendingBox.add(_marcaOffline());
      final service = buildService(attendanceClient: client);
      await service.syncPendingAttendances();

      expect(pendingBox.length, 1);
      expect(service.requiresReLogin.value, isTrue);
    });

    test('un 403 de regla de negocio no se confunde con sesion caducada',
        () async {
      // RegistrarAsistenciaView responde 403 en "dia libre", "sin turno
      // programado" o "dispositivo no autorizado". Renovar el token no lo
      // arregla: tratarlo como sesion caducada dejaria la cola atascada.
      var llamadasDeRefresh = 0;
      final refreshClient = MockClient((_) async {
        llamadasDeRefresh++;
        return http.Response('{"access":"token-nuevo"}', 200);
      });

      final client = MockClient(
        (_) async => http.Response(
          '{"detail":"Hoy esta registrado como tu Dia Libre."}',
          403,
        ),
      );

      await pendingBox.add(_marcaOffline());
      final service = buildService(
        attendanceClient: client,
        refreshClient: refreshClient,
      );
      await service.syncPendingAttendances();

      expect(llamadasDeRefresh, 0);
      expect(service.requiresReLogin.value, isFalse);
      expect(pendingBox.getAt(0)['intentos'], 1);
      expect(pendingBox.getAt(0)['ultimo_error'], contains('403'));
    });

    test('un 500 conserva la marca en la cola', () async {
      final client = MockClient((_) async => http.Response('boom', 500));

      await pendingBox.add(_marcaOffline());
      await buildService(attendanceClient: client).syncPendingAttendances();

      expect(pendingBox.length, 1);
    });

    test('una caida de red a mitad del envio conserva la marca', () async {
      final client = MockClient((_) async {
        throw const SocketException('conexion perdida');
      });

      await pendingBox.add(_marcaOffline());
      await buildService(attendanceClient: client).syncPendingAttendances();

      expect(pendingBox.length, 1);
    });

    test('un 409 (ya registrada) limpia la cola en vez de reintentar siempre',
        () async {
      var llamadas = 0;
      final client = MockClient((_) async {
        llamadas++;
        return http.Response('{"detail":"duplicado"}', 409);
      });

      await pendingBox.add(_marcaOffline());
      await buildService(attendanceClient: client).syncPendingAttendances();

      expect(pendingBox.isEmpty, isTrue);
      expect(llamadas, 1);
    });

    test('el client_uuid se persiste y se repite en cada reintento', () async {
      final uuidsEnviados = <String>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        uuidsEnviados.add(body['client_uuid'] as String);
        return http.Response('boom', 500);
      });

      // Marca encolada por una version anterior de la app: sin client_uuid.
      await pendingBox.add(_marcaOffline());
      final service = buildService(attendanceClient: client);

      await service.syncPendingAttendances();
      await service.syncPendingAttendances();

      expect(uuidsEnviados.length, 2);
      expect(uuidsEnviados.first, uuidsEnviados.last,
          reason: 'reintentar no debe generar una marca duplicada');
      expect(pendingBox.getAt(0)['client_uuid'], uuidsEnviados.first);
    });

    test('una marca rechazada se aparta tras varios intentos sin bloquear la '
        'cola', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['tipo_marcacion'] == 'Entrada') {
          return http.Response('{"detail":"datos invalidos"}', 422);
        }
        return http.Response('{"id":2}', 201);
      });

      await pendingBox.add(_marcaOffline(tipo: 'Entrada'));
      await pendingBox.add(_marcaOffline(tipo: 'Salida'));

      final service = buildService(attendanceClient: client);

      // La marca valida se sube en el primer ciclo pese al rechazo de la otra.
      await service.syncPendingAttendances();
      expect(pendingBox.length, 1);
      expect(pendingBox.getAt(0)['intentos'], 1);

      for (var i = 0; i < SyncService.maxRejectionAttempts - 1; i++) {
        await service.syncPendingAttendances();
      }

      expect(pendingBox.isEmpty, isTrue);
      final rechazadas = Hive.box(SyncService.rejectedBoxName);
      expect(rechazadas.length, 1);
      expect(rechazadas.getAt(0)['ultimo_error'], contains('422'));
    });

    test('sin salida real a Internet no se hace ninguna peticion', () async {
      var seLlamo = false;
      final client = MockClient((_) async {
        seLlamo = true;
        return http.Response('{"id":1}', 201);
      });

      await pendingBox.add(_marcaOffline());
      await buildService(
        attendanceClient: client,
        probe: () async => false,
      ).syncPendingAttendances();

      expect(seLlamo, isFalse);
      expect(pendingBox.length, 1);
    });
  });

  group('NetworkStatus: cobertura total de conectividad', () {
    test('cuenta cualquier interfaz activa, no solo movil y wifi', () {
      // Wi-Fi de un hotspot compartido desde otro celular.
      expect(
        NetworkStatus.hasActiveInterface([ConnectivityResult.wifi]),
        isTrue,
      );
      expect(
        NetworkStatus.hasActiveInterface([ConnectivityResult.mobile]),
        isTrue,
      );
      // Casos que la lista blanca anterior (`mobile || wifi`) ignoraba.
      expect(
        NetworkStatus.hasActiveInterface([ConnectivityResult.vpn]),
        isTrue,
      );
      expect(
        NetworkStatus.hasActiveInterface([ConnectivityResult.ethernet]),
        isTrue,
      );
      expect(
        NetworkStatus.hasActiveInterface([ConnectivityResult.other]),
        isTrue,
      );
      // Transicion de redes: la interfaz nueva aparece junto a la vieja.
      expect(
        NetworkStatus.hasActiveInterface(
          [ConnectivityResult.mobile, ConnectivityResult.wifi],
        ),
        isTrue,
      );

      expect(
        NetworkStatus.hasActiveInterface([ConnectivityResult.none]),
        isFalse,
      );
      expect(NetworkStatus.hasActiveInterface([]), isFalse);
    });

    test('un hotspot sin datos se detecta como sin Internet', () async {
      // El SO reporta la interfaz como conectada, pero el handshake contra la
      // API nunca llega a completarse.
      final status = NetworkStatus(
        apiUrl: 'https://ejemplo.invalido/api',
        httpClient: MockClient((_) async {
          throw const SocketException('no route to host');
        }),
      );

      expect(await status.hasRealInternet(), isFalse);
    });

    test('si la API responde (aunque sea 404) hay salida real a Internet',
        () async {
      final status = NetworkStatus(
        apiUrl: 'https://ejemplo.invalido/api',
        httpClient: MockClient((_) async => http.Response('', 404)),
      );

      expect(await status.hasRealInternet(), isTrue);
    });
  });
}

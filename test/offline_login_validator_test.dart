import 'dart:convert';

import 'package:ceneris/services/offline_login_validator.dart';
import 'package:ceneris/services/secure_credential_store.dart';
import 'package:ceneris/services/user_sync_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_credential_store_test.dart' show FakeSecureStore;

String _checksumEsperado(List<Map<String, dynamic>> usuarios) {
  final normalizados = List<Map<String, dynamic>>.from(usuarios)
    ..sort((a, b) => (a['dni'] as String).compareTo(b['dni'] as String));
  final canonical = jsonEncode(normalizados);
  return sha256.convert(utf8.encode(canonical)).toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineLoginValidator (CAV-81/82)', () {
    late FakeSecureStore fakeStore;
    late SecureCredentialStore credentialStore;

    const username = 'prueb@_01';
    const password = 'Test1234';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeStore = FakeSecureStore();
      credentialStore = SecureCredentialStore(store: fakeStore);
      await credentialStore.saveCredentialHash(
        username: username,
        password: password,
      );
    });

    /// Sincroniza (via mock) una lista de usuarios autorizados válida,
    /// para dejar "fresca" la fecha de última sincronización.
    Future<UserSyncService> syncServiceConListaValida({
      bool activo = true,
    }) async {
      final usuarios = [
        {
          'dni': '70521334',
          'username': username,
          'nombre_completo': 'Usuario Prueba',
          'activo': activo,
          'actualizado_en': DateTime.now().toIso8601String(),
        },
      ];
      final checksum = _checksumEsperado(usuarios);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'version': DateTime.now().toIso8601String(),
            'checksum': checksum,
            'usuarios': usuarios,
          }),
          200,
        );
      });

      final service = UserSyncService(
        apiUrl: 'http://127.0.0.1:8001/api',
        secureStore: fakeStore,
        httpClient: mockClient,
      );
      await service.sync(token: 'fake-token');
      return service;
    }

    test('permite el login offline con credenciales correctas y lista '
        'vigente', () async {
      final syncService = await syncServiceConListaValida();
      final validator = OfflineLoginValidator(
        userSyncService: syncService,
        credentialStore: credentialStore,
      );

      final resultado = await validator.validar(
        username: username,
        password: password,
      );

      expect(resultado.success, isTrue);
    });

    test('rechaza con contraseña incorrecta', () async {
      final syncService = await syncServiceConListaValida();
      final validator = OfflineLoginValidator(
        userSyncService: syncService,
        credentialStore: credentialStore,
      );

      final resultado = await validator.validar(
        username: username,
        password: 'contraseña-mala',
      );

      expect(resultado.success, isFalse);
      expect(
        resultado.failureReason,
        OfflineLoginFailureReason.invalidCredentials,
      );
    });

    test('rechaza si el usuario ya no esta activo en la ultima lista '
        'sincronizada', () async {
      final syncService = await syncServiceConListaValida(activo: false);
      final validator = OfflineLoginValidator(
        userSyncService: syncService,
        credentialStore: credentialStore,
      );

      final resultado = await validator.validar(
        username: username,
        password: password,
      );

      expect(resultado.success, isFalse);
      expect(
        resultado.failureReason,
        OfflineLoginFailureReason.notAuthorized,
      );
    });

    test('rechaza si la lista local nunca se sincronizo (CAV-82)',
        () async {
      // No llamamos a syncServiceConListaValida: nunca hubo sync.
      final syncService = UserSyncService(
        apiUrl: 'http://127.0.0.1:8001/api',
        secureStore: fakeStore,
      );
      final validator = OfflineLoginValidator(
        userSyncService: syncService,
        credentialStore: credentialStore,
      );

      final resultado = await validator.validar(
        username: username,
        password: password,
      );

      expect(resultado.success, isFalse);
      expect(
        resultado.failureReason,
        OfflineLoginFailureReason.authorizedListNeverSynced,
      );
    });

    test('permite el login offline aunque la ultima sincronizacion haya '
        'sido hace mucho tiempo (CAV-82: acceso indefinido, sin '
        'caducidad por dias)', () async {
      // Sincronizamos con una version/fecha muy antigua: ya no debe
      // bloquear, porque el acceso offline no caduca por tiempo.
      final usuarios = [
        {
          'dni': '70521334',
          'username': username,
          'nombre_completo': 'Usuario Prueba',
          'activo': true,
          'actualizado_en': DateTime.now().toIso8601String(),
        },
      ];
      final checksum = _checksumEsperado(usuarios);
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'version': DateTime.now()
                .subtract(const Duration(days: 200))
                .toIso8601String(),
            'checksum': checksum,
            'usuarios': usuarios,
          }),
          200,
        );
      });

      final syncService = UserSyncService(
        apiUrl: 'http://127.0.0.1:8001/api',
        secureStore: fakeStore,
        httpClient: mockClient,
      );
      await syncService.sync(token: 'fake-token');

      final validator = OfflineLoginValidator(
        userSyncService: syncService,
        credentialStore: credentialStore,
      );

      final resultado = await validator.validar(
        username: username,
        password: password,
      );

      expect(resultado.success, isTrue);
    });
  });
}

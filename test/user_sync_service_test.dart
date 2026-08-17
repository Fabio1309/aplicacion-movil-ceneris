import 'dart:convert';

import 'package:ceneris/services/user_sync_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_credential_store_test.dart' show FakeSecureStore;

/// Recalcula el checksum exactamente igual que
/// `_calcular_checksum_usuarios` en apps/api/views.py (Django), para
/// poder armar respuestas simuladas validas en los tests.
String _checksumEsperado(List<Map<String, dynamic>> usuarios) {
  final normalizados = List<Map<String, dynamic>>.from(usuarios)
    ..sort((a, b) => (a['dni'] as String).compareTo(b['dni'] as String));
  final canonical = jsonEncode(normalizados);
  return sha256.convert(utf8.encode(canonical)).toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserSyncService (CAV-182 cliente + CAV-183 integridad)', () {
    late FakeSecureStore fakeStore;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeStore = FakeSecureStore();
    });

    test('sincroniza y persiste cuando el checksum es valido', () async {
      final usuarios = [
        {
          'dni': '70521334',
          'username': 'prueb@_01',
          'nombre_completo': 'Usuario Prueba',
          'activo': true,
          'actualizado_en': '2026-08-14T10:00:00Z',
        },
      ];
      final checksum = _checksumEsperado(usuarios);

      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/usuarios-autorizados/sync/'));
        return http.Response(
          jsonEncode({
            'version': '2026-08-14T10:00:00Z',
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

      final resultado = await service.sync(token: 'fake-token');

      expect(resultado.length, 1);
      expect(resultado.first.dni, '70521334');
      expect(fakeStore.raw.containsKey('usuarios_autorizados_json'), isTrue);
    });

    test('descarta la respuesta si el checksum no coincide (CAV-183)',
        () async {
      final usuarios = [
        {
          'dni': '70521334',
          'username': 'prueb@_01',
          'nombre_completo': 'Usuario Prueba',
          'activo': true,
          'actualizado_en': '2026-08-14T10:00:00Z',
        },
      ];

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'version': '2026-08-14T10:00:00Z',
            'checksum': 'checksum-manipulado-no-valido',
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

      expect(
        () => service.sync(token: 'fake-token'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('un usuario que llega con activo=false se filtra del resultado '
        'pero se mantiene fusionado localmente', () async {
      final usuarios = [
        {
          'dni': '70521334',
          'username': 'prueb@_01',
          'nombre_completo': 'Usuario Prueba',
          'activo': false,
          'actualizado_en': '2026-08-14T10:00:00Z',
        },
      ];
      final checksum = _checksumEsperado(usuarios);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'version': '2026-08-14T10:00:00Z',
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

      final resultado = await service.sync(token: 'fake-token');
      expect(resultado, isEmpty); // inactivo -> no aparece como autorizado

      final autorizado = await service.esUsuarioAutorizado('70521334');
      expect(autorizado, isFalse);
    });

    test('lanza excepcion si el backend responde con error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"detail":"error"}', 500);
      });

      final service = UserSyncService(
        apiUrl: 'http://127.0.0.1:8001/api',
        secureStore: fakeStore,
        httpClient: mockClient,
      );

      expect(() => service.sync(token: 'fake-token'), throwsException);
    });
  });
}

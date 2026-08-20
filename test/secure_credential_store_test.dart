import 'package:ceneris/services/secure_credential_store.dart';
import 'package:ceneris/services/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Implementacion en memoria de [SecureStore] para tests (CAV-184):
/// evita depender del canal de plataforma real de flutter_secure_storage.
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

  Map<String, String> get raw => _data;
}

void main() {
  group('SecureCredentialStore (CAV-181)', () {
    late FakeSecureStore fakeStore;
    late SecureCredentialStore credentialStore;

    setUp(() {
      fakeStore = FakeSecureStore();
      credentialStore = SecureCredentialStore(store: fakeStore);
    });

    test('verifica correctamente una credencial recien guardada', () async {
      await credentialStore.saveCredentialHash(
        username: 'prueb@_01',
        password: 'Test1234',
      );

      final ok = await credentialStore.verifyCredential(
        username: 'prueb@_01',
        password: 'Test1234',
      );

      expect(ok, isTrue);
    });

    test('rechaza una contraseña incorrecta', () async {
      await credentialStore.saveCredentialHash(
        username: 'prueb@_01',
        password: 'Test1234',
      );

      final ok = await credentialStore.verifyCredential(
        username: 'prueb@_01',
        password: 'contraseña-incorrecta',
      );

      expect(ok, isFalse);
    });

    test('rechaza si no hay credencial guardada para ese usuario', () async {
      final ok = await credentialStore.verifyCredential(
        username: 'usuario_inexistente',
        password: 'cualquiera',
      );

      expect(ok, isFalse);
    });

    test('nunca persiste la contraseña en texto plano', () async {
      await credentialStore.saveCredentialHash(
        username: 'prueb@_01',
        password: 'Test1234',
      );

      final valoresGuardados = fakeStore.raw.values;
      expect(valoresGuardados.any((v) => v.contains('Test1234')), isFalse);
    });

    test('clearCredential elimina la credencial guardada', () async {
      await credentialStore.saveCredentialHash(
        username: 'prueb@_01',
        password: 'Test1234',
      );
      await credentialStore.clearCredential('prueb@_01');

      final ok = await credentialStore.verifyCredential(
        username: 'prueb@_01',
        password: 'Test1234',
      );

      expect(ok, isFalse);
    });

    test('la misma contraseña genera hashes distintos para dos usuarios '
        '(sal distinta por credencial)', () async {
      await credentialStore.saveCredentialHash(
        username: 'usuarioA',
        password: 'MismaClave123',
      );
      await credentialStore.saveCredentialHash(
        username: 'usuarioB',
        password: 'MismaClave123',
      );

      final hashA = fakeStore.raw['cred_hash_usuarioA'];
      final hashB = fakeStore.raw['cred_hash_usuarioB'];

      expect(hashA, isNotNull);
      expect(hashB, isNotNull);
      expect(hashA, isNot(equals(hashB)));
    });
  });
}

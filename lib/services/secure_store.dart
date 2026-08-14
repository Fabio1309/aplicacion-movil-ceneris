import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// CAV-180: Contrato minimo de almacenamiento cifrado clave-valor.
///
/// Se define como interfaz (en vez de usar [FlutterSecureStorage]
/// directamente en el resto del codigo) para poder inyectar una
/// implementacion en memoria durante los tests (CAV-184), sin depender
/// de canales de plataforma nativos que no existen en el entorno de test.
abstract class SecureStore {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

/// Implementacion real: delega en `flutter_secure_storage`, que persiste
/// los valores usando Android Keystore (EncryptedSharedPreferences) o
/// iOS Keychain, segun la plataforma.
class FlutterSecureCredentialStorage implements SecureStore {
  FlutterSecureCredentialStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

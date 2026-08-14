import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'secure_store.dart';

/// CAV-181: Guarda y verifica un HASH salteado de la contraseña del
/// usuario dentro del almacen cifrado (CAV-180), para permitir
/// re-validar credenciales localmente (por ejemplo, un re-login sin
/// conexion) sin persistir jamas la contraseña en texto plano.
///
/// Importante: esto NO reemplaza la autenticacion contra el backend.
/// Solo se usa para validar, en el propio dispositivo, que la persona
/// que intenta usar la app conoce la misma contraseña con la que
/// inicio sesion exitosamente la ultima vez.
class SecureCredentialStore {
  SecureCredentialStore({SecureStore? store})
      : _store = store ?? FlutterSecureCredentialStorage();

  static const _saltKeyPrefix = 'cred_salt_';
  static const _hashKeyPrefix = 'cred_hash_';

  final SecureStore _store;

  /// Genera una sal aleatoria de 16 bytes (128 bits) por credencial.
  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hash(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  /// Guarda (o reemplaza) el hash cifrado de la credencial de [username].
  /// Se debe llamar SOLO despues de un login exitoso contra el backend.
  Future<void> saveCredentialHash({
    required String username,
    required String password,
  }) async {
    final salt = _generateSalt();
    final hash = _hash(password, salt);
    await _store.write(key: '$_saltKeyPrefix$username', value: salt);
    await _store.write(key: '$_hashKeyPrefix$username', value: hash);
  }

  /// Verifica si [password] coincide con el hash guardado para [username].
  /// Devuelve `false` si no hay credencial guardada para ese usuario.
  Future<bool> verifyCredential({
    required String username,
    required String password,
  }) async {
    final salt = await _store.read(key: '$_saltKeyPrefix$username');
    final storedHash = await _store.read(key: '$_hashKeyPrefix$username');
    if (salt == null || storedHash == null) return false;

    final computedHash = _hash(password, salt);
    return _constantTimeEquals(computedHash, storedHash);
  }

  /// Comparacion en tiempo constante para evitar timing attacks al
  /// comparar hashes.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Elimina la credencial guardada de [username] (usar en logout o al
  /// desvincular el dispositivo).
  Future<void> clearCredential(String username) async {
    await _store.delete(key: '$_saltKeyPrefix$username');
    await _store.delete(key: '$_hashKeyPrefix$username');
  }
}

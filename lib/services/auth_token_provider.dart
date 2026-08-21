import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'secure_store.dart';

/// Punto único de acceso al token de sesión.
///
/// Antes, el login guardaba solo el `access` de SimpleJWT y descartaba el
/// `refresh`, así que si el token caducaba mientras el trabajador estaba sin
/// conexión no había forma de recuperarlo: las marcas pendientes se enviaban
/// con un token muerto y el servidor respondía 401.
///
/// Aquí el `refresh` se persiste en el almacén cifrado (Keystore/Keychain,
/// reutilizando [SecureStore] de CAV-180) y [refreshAccessToken] renueva el
/// `access` en segundo plano antes de reintentar la cola.
///
/// Contrato importante para quien lo consume: [refreshAccessToken] devuelve
/// `null` ante CUALQUIER fallo (no hay refresh guardado, el endpoint no existe,
/// el refresh caducó, error de red). `null` significa "no se pudo renovar",
/// nunca "descarta los datos": la cola local debe conservarse intacta.
class AuthTokenProvider {
  AuthTokenProvider({
    http.Client? httpClient,
    SecureStore? store,
    String? apiUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _store = store ?? FlutterSecureCredentialStorage(),
        _apiUrl = apiUrl ?? ApiConfig.baseUrl;

  static const accessTokenKey = 'authToken';
  static const refreshTokenKey = 'jwt_refresh_token';

  final http.Client _httpClient;
  final SecureStore _store;
  final String _apiUrl;

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(accessTokenKey);
  }

  /// Guarda los tokens tras un login exitoso. [refresh] es opcional para
  /// tolerar backends que no lo devuelvan.
  Future<void> saveTokens({required String access, String? refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accessTokenKey, access);
    if (refresh != null && refresh.isNotEmpty) {
      await _store.write(key: refreshTokenKey, value: refresh);
    }
  }

  /// Renueva el `access` contra `/token/refresh/`. Devuelve el token nuevo, o
  /// `null` si no fue posible renovarlo por cualquier motivo.
  Future<String?> refreshAccessToken() async {
    final refresh = await _readRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;

    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_apiUrl/token/refresh/'),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: json.encode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final access = data['access'] as String?;
      if (access == null || access.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(accessTokenKey, access);

      // Con ROTATE_REFRESH_TOKENS activo, SimpleJWT devuelve también un
      // refresh nuevo y el anterior queda invalidado.
      final rotated = data['refresh'] as String?;
      if (rotated != null && rotated.isNotEmpty) {
        await _store.write(key: refreshTokenKey, value: rotated);
      }

      return access;
    } catch (_) {
      // Sin conexión, endpoint inexistente, JSON inesperado: no se pudo
      // renovar. Quien llama debe conservar la cola y pedir re-login.
      return null;
    }
  }

  Future<String?> _readRefreshToken() async {
    try {
      return await _store.read(key: refreshTokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Borra el refresh cifrado (logout / desvinculación del dispositivo).
  Future<void> clearRefreshToken() async {
    try {
      await _store.delete(key: refreshTokenKey);
    } catch (_) {
      // El almacén cifrado puede no estar disponible; no debe romper el logout.
    }
  }
}

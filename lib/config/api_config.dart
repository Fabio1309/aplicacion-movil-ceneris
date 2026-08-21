// lib/config/api_config.dart
//
// Configuración centralizada de la URL base de la API.
// Cambiar de entorno = cambiar UNA sola línea (`useLocal`), sin tocar el resto
// de la app ni el servidor de producción (Render).

class ApiConfig {
  /// true  = backend local (para desarrollo en emulador Android).
  /// false = producción en Render.
  ///
  /// IMPORTANTE: dejar en `false` antes de compilar para producción.
  static const bool useLocal = false;

  /// Backend Django local (v2), vía `adb reverse tcp:8001 tcp:8001`
  /// (mas confiable en este proyecto que el alias `10.0.2.2`).
  static const String _localBaseUrl = 'http://127.0.0.1:8001/api';

  /// Producción en Render. Este valor NO modifica nada del servidor;
  /// solo indica a dónde apunta la app cuando `useLocal == false`.
  static const String _prodBaseUrl = 'https://ceneris-web-oror.onrender.com/api';

  /// URL base que usa toda la app. Siempre incluye el sufijo `/api`.
  static String get baseUrl => useLocal ? _localBaseUrl : _prodBaseUrl;
}

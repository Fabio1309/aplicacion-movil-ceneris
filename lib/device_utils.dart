// lib/device_utils.dart (o donde prefieras)

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'services/auth_token_provider.dart';

/// Clave bajo la que vive la identidad del dispositivo. El backend la usa
/// para el candado "1 trabajador = 1 celular", así que perderla equivale a
/// quedarse fuera de la app hasta que RRHH libere el equipo.
const String deviceIdKey = 'unique_device_id';

/// Obtiene un ID de dispositivo único y persistente para esta instalación de la app.
/// Si no existe uno, lo crea y lo guarda para usos futuros.
Future<String> getUniqueDeviceId() async {
  final prefs = await SharedPreferences.getInstance();

  // Buscamos si ya hemos guardado un ID único
  String? deviceId = prefs.getString(deviceIdKey);

  if (deviceId == null) {
    // Si no existe, generamos un nuevo UUID (versión 4)
    deviceId = const Uuid().v4();
    // Y lo guardamos para la próxima vez
    await prefs.setString(deviceIdKey, deviceId);
    print("[DEVICE INFO] Nuevo UUID generado y guardado: $deviceId");
  } else {
    print("[DEVICE INFO] UUID existente recuperado: $deviceId");
  }

  return deviceId;
}

/// Cierra la sesión de forma segura.
///
/// Existían dos implementaciones distintas de esto (una por pantalla) y cada
/// una se olvidaba de algo diferente: la de HomeScreen borraba el
/// `unique_device_id` junto con la sesión —lo que dejaba al trabajador
/// bloqueado por el candado de dispositivo del backend hasta que RRHH le
/// liberara el equipo— y la de DashboardScreen conservaba el ID pero dejaba
/// el refresh token vivo en el almacén cifrado, o sea una sesión renovable
/// después de cerrar sesión. Se unifican aquí para que no vuelvan a divergir.
///
/// Lo que NO toca, a propósito: la cola de asistencias pendientes en Hive.
/// Son marcas ya hechas por el trabajador; cerrar sesión no puede borrar
/// planilla. Se suben solas en cuanto alguien vuelva a iniciar sesión.
Future<void> cerrarSesion() async {
  final prefs = await SharedPreferences.getInstance();

  // La identidad del dispositivo sobrevive: no es parte de la sesión.
  final String? deviceId = prefs.getString(deviceIdKey);

  await prefs.clear();

  if (deviceId != null) {
    await prefs.setString(deviceIdKey, deviceId);
  }

  // El refresh vive en el almacén cifrado, no en prefs: hay que borrarlo
  // aparte para no dejar una sesión renovable tras el logout.
  await AuthTokenProvider().clearRefreshToken();
}

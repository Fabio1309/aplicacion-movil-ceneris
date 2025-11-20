// lib/device_utils.dart (o donde prefieras)

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Obtiene un ID de dispositivo único y persistente para esta instalación de la app.
/// Si no existe uno, lo crea y lo guarda para usos futuros.
Future<String> getUniqueDeviceId() async {
  final prefs = await SharedPreferences.getInstance();

  // Buscamos si ya hemos guardado un ID único
  String? deviceId = prefs.getString('unique_device_id');

  if (deviceId == null) {
    // Si no existe, generamos un nuevo UUID (versión 4)
    deviceId = const Uuid().v4();
    // Y lo guardamos para la próxima vez
    await prefs.setString('unique_device_id', deviceId);
    print("[DEVICE INFO] Nuevo UUID generado y guardado: $deviceId");
  } else {
    print("[DEVICE INFO] UUID existente recuperado: $deviceId");
  }

  return deviceId;
}

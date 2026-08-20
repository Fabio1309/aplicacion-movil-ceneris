import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// CAV-83: cola local de eventos "hubo un login offline" pendientes de
/// reportarle a Django. Sigue el mismo patron que ya usa
/// `SyncService`/`asistencias_pendientes`: se guarda en Hive mientras no
/// hay señal, y se vacía apenas vuelve la conexión.
class OfflineLoginEventQueue {
  OfflineLoginEventQueue({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const boxName = 'eventos_login_offline';

  final http.Client _httpClient;

  Box get _box => Hive.box(boxName);

  /// Guarda un evento pendiente de reportar. No requiere conexión.
  Future<void> enqueue({
    required String deviceId,
    required DateTime fechaHoraOffline,
  }) async {
    await _box.add({
      'device_id': deviceId,
      'fecha_hora_offline': fechaHoraOffline.toIso8601String(),
    });
  }

  bool get hayPendientes => _box.isNotEmpty;

  /// Intenta enviar todos los eventos pendientes al backend. Los que se
  /// reportan bien se eliminan de la cola; si alguno falla (sin
  /// conexión, error del servidor, etc.) se deja en la cola para el
  /// siguiente intento, sin perder los demás.
  Future<void> flush({required String apiUrl, required String token}) async {
    if (_box.isEmpty) return;

    final keysToRemove = <dynamic>[];

    for (final key in _box.keys.toList()) {
      final data = Map<String, dynamic>.from(_box.get(key));
      try {
        final response = await _httpClient
            .post(
              Uri.parse('$apiUrl/eventos/login-offline/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode(data),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 201) {
          keysToRemove.add(key);
        }
      } catch (_) {
        // Sin conexión u otro error: lo dejamos en la cola y seguimos
        // con el resto (no queremos que uno malo bloquee a los demás).
      }
    }

    if (keysToRemove.isNotEmpty) {
      await _box.deleteAll(keysToRemove);
    }
  }
}

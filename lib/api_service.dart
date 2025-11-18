// lib/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ApiService {
  // ¡IMPORTANTE! Reemplaza esto con la URL de tu servidor de Render.
  final String _baseUrl = 'https://ceneris-web-oror.onrender.com/api';

  Future<bool> solicitarHorasExtra({
    required DateTime fecha,
    required double horas,
    required String justificacion,
  }) async {
    // Intentamos recuperar token y DNI de SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final userDni = prefs.getString('user_dni');

    // Si no hay token ni dni, no podemos continuar.
    if (token == null && (userDni == null || userDni.isEmpty)) {
      throw Exception('Usuario no autenticado.');
    }

    final url = Uri.parse('$_baseUrl/horas-extra/solicitar/');

    // Construimos headers. Si hay token lo usamos; si no, hacemos un intento
    // enviando el DNI en el body como fallback (requiere soporte backend).
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Token $token';
    }

    final bodyMap = {
      'fecha_horas_extra': DateFormat('yyyy-MM-dd').format(fecha),
      'cantidad_horas': horas.toString(),
      'justificacion': justificacion,
    };

    // Si no tenemos token, incluimos el DNI como fallback para entornos de
    // desarrollo o mientras se actualiza el backend. IMPORTANTE: esto solo
    // funciona si el backend acepta este campo cuando no hay token.
    if (token == null && userDni != null && userDni.isNotEmpty) {
      bodyMap['user_dni'] = userDni;
    }

    // Log request details to help debug 404/DisallowedHost issues.
    final requestBody = json.encode(bodyMap);
    print('[API] solicitarHorasExtra -> POST $url');
    print('[API] solicitarHorasExtra -> headers=$headers');
    print('[API] solicitarHorasExtra -> body=$requestBody');

    final response = await http.post(
      url,
      headers: headers,
      body: requestBody,
    );

    if (response.statusCode == 201) {
      // 201 Created es la respuesta estándar de éxito para un POST
      return true;
    } else {
      // Registrar información útil para depuración
      print('[API] solicitarHorasExtra -> status=${response.statusCode}');
      print('[API] solicitarHorasExtra -> body=${response.body}');

      // Intentamos decodificar JSON sólo si el Content-Type lo indica.
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        try {
          final responseBody = json.decode(response.body);
          final errorMessage = responseBody.toString();
          throw Exception('Error del servidor: $errorMessage');
        } catch (e) {
          // Si falla el decode, devolvemos el cuerpo crudo.
          throw Exception(
              'Error del servidor (status ${response.statusCode}). Body: ${response.body}');
        }
      } else {
        // El servidor no devolvió JSON (posible página HTML de error)
        throw Exception(
            'Error del servidor (status ${response.statusCode}). Body: ${response.body}');
      }
    }
  }
}

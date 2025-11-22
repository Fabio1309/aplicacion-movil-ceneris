// lib/api_service.dart (VERSIÓN CORRECTA Y COMPLETA)

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';

class ApiService {
  // URL base de tu API.
  final String _baseUrl = 'https://ceneris-web-oror.onrender.com';

  // --- FUNCIÓN DE AYUDA PRIVADA ---
  // Centraliza la lógica de obtener el token y construir las cabeceras.
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('authToken');

    if (token == null) {
      throw Exception(
          'Token de autenticación no encontrado. Inicie sesión de nuevo.');
    }

    // Usa el prefijo 'Bearer' para el token JWT.
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  // --- FUNCIÓN PARA SOLICITAR HORAS EXTRA (CORREGIDA) ---
  Future<bool> solicitarHorasExtra({
    required DateTime fecha,
    required double horas,
    required String justificacion,
  }) async {
    try {
      // 1. Obtiene las cabeceras que incluyen el token.
      final headers = await _getAuthHeaders();

      // 2. Construye la URL completa del endpoint.
      final url = Uri.parse('$_baseUrl/api/horas-extra/solicitar/');

      // 3. Prepara el cuerpo de la petición.
      final body = json.encode({
        'fecha_horas_extra':
            DateFormat('yyyy-MM-dd').format(fecha), // Antes: fecha_solicitud
        'cantidad_horas': horas,
        'justificacion': justificacion, // Antes: motivo
      });

      // 4. Realiza la petición POST, ahora CON las cabeceras de autenticación.
      final response = await http.post(url, headers: headers, body: body);

      // 5. Verifica si la solicitud fue exitosa.
      if (response.statusCode == 201) {
        // 201 Created
        return true; // Éxito
      } else {
        // Decodificación segura del error
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        // Si devuelve un diccionario de errores, trata de mostrar el primero
        print("Error del servidor: $errorData");

        final errorMessage = errorData.toString();
        throw Exception("Error al solicitar: $errorMessage");
      }
    } catch (e) {
      // Relanza la excepción para que la UI (la pantalla) la pueda capturar y mostrar.
      print("Error en ApiService.solicitarHorasExtra: $e");
      rethrow;
    }
  }

  // Aquí puedes añadir más funciones de API en el futuro.
}

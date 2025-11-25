// lib/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ApiService {
  // URL base de tu API en Render
  final String _baseUrl = 'https://ceneris-web-oror.onrender.com';

  // --- 1. FUNCIÓN DE AYUDA PRIVADA ---
  // Obtiene el token y prepara los headers
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('authToken');

    if (token == null) {
      throw Exception(
          'Token de autenticación no encontrado. Inicie sesión de nuevo.');
    }

    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  // --- 2. SOLICITAR HORAS EXTRA ---
  Future<bool> solicitarHorasExtra({
    required DateTime fecha,
    required double horas,
    required String justificacion,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/horas-extra/solicitar/');

      final body = json.encode({
        'fecha_horas_extra': DateFormat('yyyy-MM-dd').format(fecha),
        'cantidad_horas': horas,
        'justificacion': justificacion,
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 201) {
        return true;
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        print("Error del servidor: $errorData");
        throw Exception("Error al solicitar: $errorData");
      }
    } catch (e) {
      print("Error en solicitarHorasExtra: $e");
      rethrow;
    }
  }

  // --- 3. OBTENER MIS SOLICITUDES DE H.E. ---
  Future<List<dynamic>> obtenerMisSolicitudesHE() async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/horas-extra/mis-solicitudes/');

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('Error al cargar historial de H.E.');
      }
    } catch (e) {
      print("Error en obtenerMisSolicitudesHE: $e");
      rethrow;
    }
  }

  // --- 4. OBTENER HISTORIAL DE ASISTENCIA (CALENDARIO) ---
  // Conecta con la vista HistorialAsistenciaView de Django
  Future<List<dynamic>> obtenerHistorialAsistencia(int mes, int anio) async {
    try {
      final headers = await _getAuthHeaders();
      // Pasamos mes y año como Query Params
      final url =
          Uri.parse('$_baseUrl/api/historial-asistencia/?mes=$mes&anio=$anio');

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        // Retorna la lista de objetos con 'resultado', 'hora_entrada_real', etc.
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        print("Error Server: ${response.statusCode} - ${response.body}");
        throw Exception('Error al cargar historial de asistencia');
      }
    } catch (e) {
      print("Error en obtenerHistorialAsistencia: $e");
      return []; // Retorna lista vacía en caso de error para no romper la UI
    }
  }

  // --- 5. ENVIAR JUSTIFICACIÓN (DESDE CALENDARIO) ---
  // Unificada: Envía JSON con la fecha seleccionada
  Future<bool> enviarJustificacion(
      String fecha, String motivo, String descripcion) async {
    try {
      final headers = await _getAuthHeaders();
      // Ajusta esta ruta si decidiste usar otra en urls.py
      final url = Uri.parse('$_baseUrl/api/justificaciones/crear/');

      final body = json.encode({
        'fecha': fecha, // Formato "YYYY-MM-DD"
        'motivo': motivo,
        'descripcion': descripcion
      });

      final response = await http.post(url, headers: headers, body: body);

      // Aceptamos 200 o 201 como éxito
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print("Error al justificar: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error enviando justificación: $e");
      return false;
    }
  }
}

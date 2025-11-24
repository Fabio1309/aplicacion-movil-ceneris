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

  Future<List<Map<String, dynamic>>> obtenerHistorialAsistencia() async {
    // SIMULACIÓN: Esto debería ser un GET a tu endpoint de Django /api/tareo-diario/
    await Future.delayed(const Duration(seconds: 1)); // Simular red

    return [
      {
        "fecha": "2023-11-20",
        "resultado": "A", // Asistió
        "hora_entrada_programada": "08:00",
        "hora_salida_programada": "17:00",
        "hora_entrada_real": "07:55",
        "hora_salida_real": "17:02",
      },
      {
        "fecha": "2023-11-21",
        "resultado": "F", // Falta
        "hora_entrada_programada": "08:00",
        "hora_salida_programada": "17:00",
        "hora_entrada_real": null,
        "hora_salida_real": null,
        "justificacion_estado":
            null, // null = sin justificar, 'PENDIENTE', 'APROBADO'
      },
      {
        "fecha": "2023-11-22",
        "resultado": "F",
        "hora_entrada_programada": "08:00",
        "hora_salida_programada": "17:00",
        "justificacion_estado": "PENDIENTE", // Ya envió justificación
      }
    ];
  }

  Future<bool> enviarJustificacion(
      String fecha, String motivo, String descripcion) async {
    // Aquí iría tu POST a Django
    await Future.delayed(const Duration(seconds: 2));
    return true;
  }

  Future<List<dynamic>> obtenerMisSolicitudesHE() async {
    final headers = await _getAuthHeaders();
    final url = Uri.parse('$_baseUrl/api/horas-extra/mis-solicitudes/');

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      // Decodificamos la lista de solicitudes
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Error al cargar historial');
    }
  }

  // FUNCION PARA ENVIO DE JUSTIFICACIONES
  Future<List<dynamic>> obtenerFaltasPendientes() async {
    final headers = await _getAuthHeaders();
    final url = Uri.parse('$_baseUrl/api/faltas/pendientes/');

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Error al cargar faltas');
    }
  }

  // --- ENVIAR JUSTIFICACIÓN CON ARCHIVO ---
  Future<bool> enviarJustificacion({
    required int tareoId,
    required String motivo,
    required String descripcion,
    File? archivo, // Puede ser null
  }) async {
    final headers = await _getAuthHeaders(); // Tu función que obtiene el Token
    final token =
        headers['Authorization']!; // Extraemos solo el string "Bearer ..."

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/faltas/justificar/'),
    );

    // Agregar headers (Authorization es clave aquí)
    request.headers['Authorization'] = token;

    // Agregar campos de texto
    request.fields['tareo'] = tareoId.toString();
    request.fields['motivo'] = motivo;
    request.fields['descripcion'] = descripcion;

    // Agregar archivo si existe
    if (archivo != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'archivo_evidencia',
        archivo.path,
      ));
    }

    // Enviar
    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return true;
      } else {
        print("Error server: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Error enviando archivo: $e");
      return false;
    }
  }
}

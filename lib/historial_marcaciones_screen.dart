import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'app_colors.dart';
import 'config/api_config.dart';

class HistorialMarcacionesScreen extends StatefulWidget {
  const HistorialMarcacionesScreen({super.key});

  @override
  State<HistorialMarcacionesScreen> createState() =>
      _HistorialMarcacionesScreenState();
}

class _HistorialMarcacionesScreenState
    extends State<HistorialMarcacionesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _marcaciones = [];
  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> listaCombinada = [];

    // 1. CARGAR LOCALES (OFFLINE / PENDIENTES)
    // Leemos de Hive lo que aún no se ha subido
    var box = Hive.box('asistencias_pendientes');
    for (var key in box.keys) {
      final data = box.get(key);
      listaCombinada.add({
        'tipo': data['tipo_marcacion'],
        'fecha_hora': data['timestamp'], // Viene en ISO String
        'ubicacion': data['nombre_ubicacion'] ?? 'Ubicación Desconocida',
        'es_offline': true, // BANDERA IMPORTANTE
      });
    }

    // 2. CARGAR REMOTAS (DEL SERVIDOR)
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$_baseUrl/asistencias/log/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> serverData =
            json.decode(utf8.decode(response.bodyBytes));
        for (var item in serverData) {
          listaCombinada.add({
            'tipo': item['tipo'],
            'fecha_hora': item['fecha_hora'],
            'ubicacion': item['ubicacion'],
            'es_offline': false,
          });
        }
      }
    } catch (e) {
      print("Error cargando historial remoto: $e");
    }

    // 3. ORDENAR POR FECHA DESCENDENTE (Lo más reciente primero)
    listaCombinada.sort((a, b) {
      DateTime fechaA = DateTime.parse(a['fecha_hora']);
      DateTime fechaB = DateTime.parse(b['fecha_hora']);
      return fechaB.compareTo(fechaA);
    });

    if (mounted) {
      setState(() {
        _marcaciones = listaCombinada;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. CABECERA (mismo naranja del resto de la app; se extiende
            // detrás de la barra de estado). Botón de volver a la derecha,
            // en blanco con ícono naranja, igual que en las demás pantallas.
            Container(
              padding: EdgeInsets.fromLTRB(
                  24, 20 + MediaQuery.of(context).padding.top, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.7),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Historial de\nMarcas',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ]),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.primary, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),

            // 2. CONTENIDO
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _cargarDatos,
                      child: _marcaciones.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _marcaciones.length,
                              itemBuilder: (context, index) {
                                final item = _marcaciones[index];
                                return _buildMarcacionCard(item);
                              },
                            ),
                    ),
            ),

            // 3. FOOTER: banda naranja plana con un recordatorio
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withOpacity(0.7),
                  ],
                ),
              ),
              child: const Center(
                child: Text(
                  'Recuerda marcar tus asistencias',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarcacionCard(Map<String, dynamic> item) {
    final bool esOffline = item['es_offline'];
    final bool esEntrada = item['tipo'] == 'Entrada';

    // Formatear fecha bonita
    final DateTime fecha = DateTime.parse(item['fecha_hora']);
    final String horaStr = DateFormat('hh:mm a').format(fecha);
    final String fechaStr = DateFormat('dd/MM/yyyy').format(fecha);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: esOffline
            ? Border.all(
                color: Colors.orange.withOpacity(0.5),
                width: 1.5) // Borde naranja si es offline
            : Border.all(color: const Color(0xFFF6FBFE)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.18),
            spreadRadius: 1,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // ICONO DE ENTRADA/SALIDA
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: esEntrada
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              esEntrada ? Icons.login : Icons.logout,
              color: esEntrada ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 15),

          // INFO DE TEXTO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['tipo'].toString().toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$fechaStr - $horaStr",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  item['ubicacion'],
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ESTADO DE SINCRONIZACIÓN (LA CLAVE DE TU PREGUNTA)
          Column(
            children: [
              Icon(
                esOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                color: esOffline ? Colors.orange : Colors.blue,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                esOffline ? "Pendiente" : "Enviado",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: esOffline ? Colors.orange : Colors.blue,
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 60, color: Colors.grey),
          SizedBox(height: 16),
          Text("No hay marcaciones recientes"),
        ],
      ),
    );
  }
}

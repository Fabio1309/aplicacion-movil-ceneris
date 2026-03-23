import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class JustificarAusenciaScreen extends StatefulWidget {
  const JustificarAusenciaScreen({super.key});

  @override
  _JustificarAusenciaScreenState createState() =>
      _JustificarAusenciaScreenState();
}

class _JustificarAusenciaScreenState extends State<JustificarAusenciaScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, dynamic> _dataPorFecha = {};
  bool _isLoading = true;
  final String _baseUrl = 'https://ceneris-web-oror.onrender.com/api';

  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  String? _motivoSeleccionado;
  bool _enviando = false;

  final List<String> _motivosDjango = [
    'SALUD',
    'PERSONAL',
    'TRAMITE',
    'TRANSPORTE',
    'OTRO'
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _cargarHistorial();
  }

  // --- HELPER PARA COMPARAR FECHAS SIN HORA ---
  bool _esFuturo(DateTime dia) {
    final now = DateTime.now();
    final hoySinHora = DateTime(now.year, now.month, now.day);
    final diaSinHora = DateTime(dia.year, dia.month, dia.day);
    return diaSinHora.isAfter(hoySinHora);
  }
  // --------------------------------------------

  Future<void> _cargarHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final mes = _focusedDay.month;
    final anio = _focusedDay.year;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/historial-asistencia/?mes=$mes&anio=$anio'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> lista =
            json.decode(utf8.decode(response.bodyBytes));
        final Map<String, dynamic> mapaTemp = {};
        for (var item in lista) {
          mapaTemp[item['fecha']] = item;
        }
        if (mounted)
          setState(() {
            _dataPorFecha = mapaTemp;
            _isLoading = false;
          });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enviarJustificacion(Function setStateDialog) async {
    if (!_formKey.currentState!.validate()) return;

    setStateDialog(() => _enviando = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    try {
      final bodyMap = {
        "fecha": DateFormat('yyyy-MM-dd').format(_selectedDay!),
        "motivo": _motivoSeleccionado,
        "descripcion": _descripcionController.text
      };

      final String bodyJson = json.encode(bodyMap);

      // --- 🔍 INICIO DEPURACIÓN ---
      final Uri urlCompleta = Uri.parse('$_baseUrl/justificaciones/crear/');

      print("\n🔵 ================= SOLICITUD HTTP =================");
      print("📡 URL DESTINO: $urlCompleta");
      print(
          "🔑 TOKEN: Bearer ${token?.substring(0, 10)}..."); // Solo mostramos el inicio por seguridad
      print("📦 BODY (DATOS): $bodyJson");
      print("===================================================\n");
      // -----------------------------

      final response = await http.post(urlCompleta,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token'
          },
          body: bodyJson);

      // --- 🔍 RESPUESTA DEPURACIÓN ---
      print("\n🟠 ================= RESPUESTA SERVIDOR =================");
      print("STATUS CODE: ${response.statusCode}");
      print("CUERPO RESPUESTA: ${response.body}");
      print("=====================================================\n");
      // ------------------------------

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context); // Cerrar modal
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Justificación enviada correctamente'),
              backgroundColor: Colors.green));
          _cargarHistorial();
        }
      } else {
        // Si falla, lanzamos error para que caiga en el catch y muestre el snackbar
        throw Exception("Error ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("❌ ERROR EXCEPCIÓN: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setStateDialog(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaKey = _selectedDay != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDay!)
        : "";
    final datosDia = _dataPorFecha[fechaKey];

    return Scaffold(
      appBar: AppBar(title: const Text("Gestión de Asistencia")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCalendario(),
                const Divider(thickness: 1, height: 1),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.grey[50],
                    padding: const EdgeInsets.all(20),
                    child: datosDia != null
                        ? _buildPanelDetalle(datosDia)
                        : _buildEmptyState(),
                  ),
                )
              ],
            ),
    );
  }

  Widget _buildCalendario() {
    return TableCalendar(
      locale: 'es_ES',
      firstDay: DateTime.utc(2023, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        if (_focusedDay.month != focusedDay.month) {
          Future.delayed(Duration.zero, () => _cargarHistorial());
        }
      },
      calendarStyle: const CalendarStyle(
        todayDecoration:
            BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
        selectedDecoration:
            BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
      ),
      eventLoader: (day) {
        final key = DateFormat('yyyy-MM-dd').format(day);
        return _dataPorFecha.containsKey(key) ? [_dataPorFecha[key]] : [];
      },
      calendarBuilders: CalendarBuilders(
        singleMarkerBuilder: (context, date, event) {
          final data = event as Map<String, dynamic>;
          Color color = Colors.grey;

          // --- CAMBIO 1: VALIDAR FUTURO VISUALMENTE ---
          bool esFuturo = _esFuturo(date);

          if (esFuturo) {
            // Si es futuro, aunque la BD diga 'F', lo pintamos gris/azul (Programado)
            color = Colors.blueGrey.withOpacity(0.5);
          } else {
            // Si es hoy o pasado, respetamos el color real
            if (data['resultado'] == 'A') color = Colors.green;
            if (data['resultado'] == 'F') color = Colors.red;
          }
          // ---------------------------------------------

          return Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            width: 7.0,
            height: 7.0,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
          );
        },
      ),
    );
  }

  Widget _buildPanelDetalle(Map<String, dynamic> data) {
    bool esFalta = data['resultado'] == 'F';
    bool esAsistencia = data['resultado'] == 'A';
    String? estadoJustificacion = data['justificacion_estado'];
    double tardanza = double.tryParse(data['tardanza_horas'].toString()) ?? 0.0;

    // --- CAMBIO 2: DETECTAR SI ES FUTURO PARA EL PANEL ---
    // Usamos _selectedDay que es el día que el usuario tocó
    bool esFuturo = _esFuturo(_selectedDay!);
    // -----------------------------------------------------

    // Si es futuro, forzamos que NO se vea como Falta, sino como Programado
    if (esFuturo) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month_outlined, size: 60, color: Colors.blueGrey),
          const SizedBox(height: 15),
          Text(
            "TURNO PROGRAMADO",
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey),
          ),
          const SizedBox(height: 8),
          Text(DateFormat.yMMMMEEEEd('es_ES').format(_selectedDay!),
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300)),
            child: Column(
              children: [
                _buildTimeRow("Entrada", data['entrada_prog'] ?? '--:--',
                    Icons.wb_sunny_outlined),
                Divider(),
                _buildTimeRow("Salida", data['salida_prog'] ?? '--:--',
                    Icons.nights_stay_outlined),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text("Este día aún no ha transcurrido.",
              style:
                  TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
        ],
      );
    }

    // --- EL RESTO DE LA LÓGICA (PASADO Y HOY) SE MANTIENE IGUAL ---
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    esFalta ? Icons.cancel : Icons.check_circle,
                    color: esFalta ? Colors.red : Colors.green,
                    size: 40,
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        esFalta ? "FALTA" : "ASISTENCIA",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: esFalta ? Colors.red : Colors.green),
                      ),
                      Text(DateFormat.yMMMMEEEEd('es_ES').format(_selectedDay!),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (esAsistencia) ...[
            const Text("Resumen de Jornada",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            _buildTimeRow(
                "Entrada Programada", data['entrada_prog'], Icons.access_time),
            _buildTimeRow(
                "Entrada Real", data['entrada_real'] ?? '--:--', Icons.login,
                isReal: true),
            const Divider(),
            _buildTimeRow(
                "Salida Programada", data['salida_prog'], Icons.access_time),
            _buildTimeRow(
                "Salida Real", data['salida_real'] ?? '--:--', Icons.logout,
                isReal: true),
            if (tardanza > 0)
              Container(
                margin: const EdgeInsets.only(top: 15),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text("Tardanza registrada: $tardanza hrs",
                            style: const TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold))),
                  ],
                ),
              )
          ],
          if (esFalta) ...[
            const Text("Detalle",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            const Text("No se registraron marcaciones válidas para este día."),
            const SizedBox(height: 30),
            if (estadoJustificacion == null)
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _abrirModalJustificacion,
                  icon: const Icon(Icons.edit_document),
                  label: const Text("JUSTIFICAR FALTA"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Colors.blue[50],
                    border: Border.all(color: Colors.blue),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 30),
                    const SizedBox(height: 10),
                    Text("Justificación Enviada",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900])),
                    Text("Estado: $estadoJustificacion"),
                  ],
                ),
              )
          ]
        ],
      ),
    );
  }

  Widget _buildTimeRow(String label, String time, IconData icon,
      {bool isReal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.black87)),
          ]),
          Text(time,
              style: TextStyle(
                  fontWeight: isReal ? FontWeight.bold : FontWeight.normal,
                  fontSize: isReal ? 16 : 14,
                  color: isReal ? Colors.black : Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
        child: Text("Sin información para este día (Día Libre)"));
  }

  void _abrirModalJustificacion() {
    _motivoSeleccionado = null;
    _descripcionController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Justificar Falta"),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          "Fecha: ${DateFormat('dd/MM/yyyy').format(_selectedDay!)}"),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                            labelText: 'Motivo', border: OutlineInputBorder()),
                        items: _motivosDjango
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (val) =>
                            setStateDialog(() => _motivoSeleccionado = val),
                        validator: (v) =>
                            v == null ? 'Seleccione un motivo' : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _descripcionController,
                        decoration: const InputDecoration(
                            labelText: 'Descripción / Detalle',
                            border: OutlineInputBorder()),
                        maxLines: 3,
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: _enviando ? null : () => Navigator.pop(context),
                    child: const Text("Cancelar")),
                ElevatedButton(
                  onPressed: _enviando
                      ? null
                      : () => _enviarJustificacion(setStateDialog),
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Enviar"),
                )
              ],
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'api_service.dart'; // Asegúrate de importar tu servicio

class JustificarAusenciaScreen extends StatefulWidget {
  const JustificarAusenciaScreen({super.key});

  @override
  _JustificarAusenciaScreenState createState() =>
      _JustificarAusenciaScreenState();
}

class _JustificarAusenciaScreenState extends State<JustificarAusenciaScreen> {
  final ApiService _api = ApiService();

  // Calendario
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Datos: Mapa donde la clave es la fecha "YYYY-MM-DD"
  Map<String, dynamic> _asistenciasPorFecha = {};
  bool _isLoading = true;

  // Formulario de Justificación
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  String? _motivoSeleccionado;
  bool _enviando = false;

  // Lista de motivos coincidente con tu modelo Django
  final List<String> _listaMotivos = [
    'SALUD',
    'PERSONAL',
    'TRAMITE',
    'TRANSPORTE',
    'OTRO',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _cargarAsistencias();
  }

  Future<void> _cargarAsistencias() async {
    try {
      final lista = await _api.obtenerHistorialAsistencia(); // Tu método API
      final Map<String, dynamic> mapaTemp = {};

      for (var item in lista) {
        String fechaStr = item['fecha'];
        mapaTemp[fechaStr] = item;
      }

      setState(() {
        _asistenciasPorFecha = mapaTemp;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fechaAString(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Color del punto en el calendario
  Color _getColorEstado(String resultado) {
    if (resultado == 'F') return Colors.red; // Falta
    if (resultado == 'A' || resultado == 'P') return Colors.green; // Asistió
    return Colors.grey;
  }

  // --- LÓGICA DEL POPUP DE JUSTIFICACIÓN ---
  void _abrirFormularioJustificacion() {
    _descripcionController.clear();
    _motivoSeleccionado = null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Justificar Inasistencia"),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Fecha: ${_fechaAString(_selectedDay!)}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      // Dropdown Motivo
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Motivo',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        value: _motivoSeleccionado,
                        items: _listaMotivos.map((motivo) {
                          return DropdownMenuItem(
                            value: motivo,
                            child: Text(motivo),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setStateDialog(() => _motivoSeleccionado = val),
                        validator: (val) =>
                            val == null ? 'Seleccione un motivo' : null,
                      ),
                      const SizedBox(height: 15),
                      // Text Area Descripción
                      TextFormField(
                        controller: _descripcionController,
                        decoration: const InputDecoration(
                          labelText: 'Detalle de la justificación',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        validator: (value) =>
                            value!.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 10),
                      // Botón simulado para subir archivo (solo visual por ahora)
                      OutlinedButton.icon(
                        onPressed: () {
                          // Aquí integrarías image_picker o file_picker
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  "Funcionalidad de archivo pendiente de implementar")));
                        },
                        icon: const Icon(Icons.attach_file),
                        label: const Text("Adjuntar Evidencia (Opcional)"),
                      )
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _enviando ? null : () => Navigator.of(context).pop(),
                  child: const Text("CANCELAR",
                      style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: _enviando
                      ? null
                      : () => _enviarJustificacion(setStateDialog),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text("ENVIAR",
                          style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _enviarJustificacion(Function setStateDialog) async {
    if (!_formKey.currentState!.validate()) return;

    setStateDialog(() => _enviando = true);

    try {
      final success = await _api.enviarJustificacion(
          _fechaAString(_selectedDay!),
          _motivoSeleccionado!,
          _descripcionController.text);

      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Justificación enviada para revisión.'),
              backgroundColor: Colors.green),
        );
        // Recargar datos para que cambie el estado (ej: a Pendiente)
        _cargarAsistencias();
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setStateDialog(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaStr = _selectedDay != null ? _fechaAString(_selectedDay!) : "";
    final registroDia = _asistenciasPorFecha[fechaStr];

    return Scaffold(
      appBar: AppBar(title: const Text('Mis Asistencias')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTableCalendar(),
                const SizedBox(height: 10),
                const Divider(thickness: 1),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20.0),
                    color: Colors.grey[50],
                    child: registroDia != null
                        ? _buildDetalleDia(registroDia)
                        : _buildEmptyState(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTableCalendar() {
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
      },
      calendarStyle: const CalendarStyle(
        todayDecoration:
            BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
        selectedDecoration:
            BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
      ),
      eventLoader: (day) {
        final key = _fechaAString(day);
        return _asistenciasPorFecha.containsKey(key)
            ? [_asistenciasPorFecha[key]]
            : [];
      },
      calendarBuilders: CalendarBuilders(
        singleMarkerBuilder: (context, date, event) {
          final data = event as Map<String, dynamic>;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getColorEstado(
                  data['resultado']), // Rojo si es F, Verde si es A
            ),
            width: 7.0,
            height: 7.0,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
          );
        },
      ),
    );
  }

  // Vista cuando NO hay registro en la DB (ej: día futuro o fin de semana libre)
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 50, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text("Sin registro de actividad",
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // Vista principal de detalle
  Widget _buildDetalleDia(Map<String, dynamic> data) {
    bool esFalta = data['resultado'] == 'F';
    bool yaJustifico = data['justificacion_estado'] != null;

    return SingleChildScrollView(
      child: Column(
        children: [
          // TARJETA DE ESTADO
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Icon(
                    esFalta
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: esFalta ? Colors.red : Colors.green,
                    size: 50,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    esFalta ? "FALTA REGISTRADA" : "ASISTENCIA CORRECTA",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: esFalta ? Colors.red : Colors.green),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateFormat.yMMMMEEEEd('es_ES').format(_selectedDay!),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // TARJETA DE HORARIOS (Comparativa)
          Card(
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Detalle de Jornada",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _buildHorarioRow("Entrada Programada",
                      data['hora_entrada_programada'] ?? '--:--'),
                  _buildHorarioRow("Salida Programada",
                      data['hora_salida_programada'] ?? '--:--'),
                  const Divider(),
                  _buildHorarioRow("Entrada Real",
                      data['hora_entrada_real'] ?? 'No registrada',
                      esRojo: esFalta),
                  _buildHorarioRow("Salida Real",
                      data['hora_salida_real'] ?? 'No registrada',
                      esRojo: esFalta),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // BOTÓN DE ACCIÓN (Solo si es falta)
          if (esFalta) ...[
            if (!yaJustifico)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _abrirFormularioJustificacion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.edit_document, color: Colors.white),
                  label: const Text("JUSTIFICAR FALTA",
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Estado de justificación: ${data['justificacion_estado']}",
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              )
          ]
        ],
      ),
    );
  }

  Widget _buildHorarioRow(String label, String time, {bool esRojo = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(time,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: esRojo && time.contains('No')
                      ? Colors.red
                      : Colors.black87)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class SolicitudHorasExtraScreen extends StatefulWidget {
  const SolicitudHorasExtraScreen({super.key});

  @override
  _SolicitudHorasExtraScreenState createState() =>
      _SolicitudHorasExtraScreenState();
}

class _SolicitudHorasExtraScreenState extends State<SolicitudHorasExtraScreen> {
  final ApiService _api = ApiService();

  // Calendario
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Datos
  Map<String, dynamic> _solicitudesPorFecha = {};
  bool _isLoading = true;

  // Formulario
  final _formKey = GlobalKey<FormState>();
  final _horasController = TextEditingController();
  final _justificacionController = TextEditingController();
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _cargarSolicitudes();
  }

  Future<void> _cargarSolicitudes() async {
    try {
      final lista = await _api.obtenerMisSolicitudesHE();
      final Map<String, dynamic> mapaTemp = {};

      for (var sol in lista) {
        String fechaStr = sol['fecha_horas_extra'];
        mapaTemp[fechaStr] = sol;
      }

      setState(() {
        _solicitudesPorFecha = mapaTemp;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error cargando historial")));
      }
    }
  }

  // Función auxiliar para fechas
  String _fechaAString(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Color _getColorEstado(String estado) {
    if (estado == 'APROBADO') return Colors.green;
    if (estado == 'RECHAZADO') return Colors.red;
    return Colors.orange;
  }

  // --- LÓGICA DEL FORMULARIO Y ENVÍO ---

  // 1. Función para abrir la ventana emergente
  void _abrirFormularioPopup() {
    // Limpiamos los controladores antes de abrir
    _horasController.clear();
    _justificacionController.clear();

    showDialog(
      context: context,
      barrierDismissible: false, // Obliga a usar botones para cerrar
      builder: (BuildContext context) {
        return StatefulBuilder(
          // StatefulBuilder es necesario para actualizar el estado (loading) DENTRO del dialogo
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text("Solicitud para el ${_fechaAString(_selectedDay!)}"),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Se ajusta al contenido
                    children: [
                      TextFormField(
                        controller: _horasController,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad de Horas',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'Requerido';
                          if (double.tryParse(value) == null)
                            return 'Número inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _justificacionController,
                        decoration: const InputDecoration(
                          labelText: 'Motivo / Justificación',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        validator: (value) =>
                            value!.isEmpty ? 'Requerido' : null,
                      ),
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
                      : () => _enviarSolicitud(
                          setStateDialog), // Pasamos el setState del dialogo
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

  // 2. Función de envío modificada para cerrar el diálogo
  Future<void> _enviarSolicitud(Function setStateDialog) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDay == null) return;

    // Usamos el setState del dialogo para mostrar el loading en el botón
    setStateDialog(() => _enviando = true);

    try {
      final success = await _api.solicitarHorasExtra(
        fecha: _selectedDay!,
        horas: double.parse(_horasController.text),
        justificacion: _justificacionController.text,
      );

      if (success && mounted) {
        Navigator.of(context).pop(); // CERRAR EL POPUP

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Solicitud enviada con éxito.'),
              backgroundColor: Colors.green),
        );

        // Recargamos calendario para que aparezca el punto
        await _cargarSolicitudes();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setStateDialog(() => _enviando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Verificamos si el día seleccionado ya tiene solicitud
    final solicitudDia = _selectedDay != null
        ? _solicitudesPorFecha[_fechaAString(_selectedDay!)]
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario Horas Extra')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTableCalendar(),
                const SizedBox(height: 10),
                const Divider(thickness: 1),

                // ZONA INFERIOR DINÁMICA
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20.0),
                    color: Colors.grey[100],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // CASO 1: Si hay solicitud, mostramos detalles
                        if (solicitudDia != null)
                          Expanded(
                              child: SingleChildScrollView(
                                  child: _buildDetalleSolicitud(solicitudDia))),

                        // CASO 2: Si NO hay solicitud y hay día seleccionado, mostramos botón
                        if (solicitudDia == null && _selectedDay != null) ...[
                          const Icon(Icons.calendar_today,
                              size: 60, color: Colors.blueGrey),
                          const SizedBox(height: 10),
                          Text(
                            "No hay solicitudes para el ${_fechaAString(_selectedDay!)}",
                            style: const TextStyle(
                                fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _abrirFormularioPopup,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text("SOLICITAR HORAS EXTRA"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 15),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ],
                    ),
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
        if (_solicitudesPorFecha.containsKey(key)) {
          return [_solicitudesPorFecha[key]];
        }
        return [];
      },
      calendarBuilders: CalendarBuilders(
        singleMarkerBuilder: (context, date, event) {
          final solicitud = event as Map<String, dynamic>;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getColorEstado(solicitud['estado']),
            ),
            width: 7.0,
            height: 7.0,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
          );
        },
      ),
    );
  }

  Widget _buildDetalleSolicitud(Map<String, dynamic> solicitud) {
    return Card(
      elevation: 0, // Quitamos elevación para que se vea plano en el fondo gris
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info, color: _getColorEstado(solicitud['estado'])),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Estado: ${solicitud['estado']}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                  // Esto asegura que si es muy largo, baje a la siguiente línea
                  softWrap: true,
                ),
              ),
            ]),
            const Divider(height: 30),
            Text("Horas solicitadas: ${solicitud['cantidad_horas']}",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            const Text("Justificación:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(solicitud['justificacion']),
            const SizedBox(height: 20),
            if (solicitud['estado'].contains('PENDIENTE'))
              const Text("Tu solicitud está siendo revisada.",
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey)),
            if (solicitud['estado'] == 'RECHAZADO')
              Text(
                  "Motivo rechazo: ${solicitud['motivo_rechazo'] ?? 'No especificado'}",
                  style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

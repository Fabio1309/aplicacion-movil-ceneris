import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'api_service.dart';

class ListaFaltasScreen extends StatefulWidget {
  @override
  _ListaFaltasScreenState createState() => _ListaFaltasScreenState();
}

class _ListaFaltasScreenState extends State<ListaFaltasScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _faltas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarFaltas();
  }

  Future<void> _cargarFaltas() async {
    try {
      final data = await _api.obtenerFaltasPendientes();
      setState(() {
        _faltas = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _abrirFormulario(Map<String, dynamic> falta) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FormularioJustificacion(
        tareoId: falta['id'],
        fechaStr: falta['fecha'],
        onSuccess: () {
          Navigator.pop(context);
          _cargarFaltas(); // Recargar lista al terminar
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Justificación enviada correctamente"))
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator());
    if (_faltas.isEmpty) return Center(child: Text("No tienes faltas pendientes de justificar."));

    return ListView.builder(
      itemCount: _faltas.length,
      itemBuilder: (ctx, i) {
        final f = _faltas[i];
        return Card(
          child: ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text("Falta: ${f['fecha']}"),
            subtitle: Text(f['dia_semana']),
            trailing: ElevatedButton(
              onPressed: () => _abrirFormulario(f),
              child: Text("Justificar"),
            ),
          ),
        );
      },
    );
  }
}

// --- SUB-WIDGET: FORMULARIO ---
class FormularioJustificacion extends StatefulWidget {
  final int tareoId;
  final String fechaStr;
  final VoidCallback onSuccess;

  const FormularioJustificacion({required this.tareoId, required this.fechaStr, required this.onSuccess});

  @override
  _FormularioJustificacionState createState() => _FormularioJustificacionState();
}

class _FormularioJustificacionState extends State<FormularioJustificacion> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final ApiService _api = ApiService();
  
  String _motivoSeleccionado = 'SALUD';
  File? _archivoSeleccionado;
  bool _enviando = false;

  final List<Map<String, String>> _opciones = [
    {'val': 'SALUD', 'label': 'Salud / Médica'},
    {'val': 'PERSONAL', 'label': 'Personal'},
    {'val': 'TRAMITE', 'label': 'Trámite'},
    {'val': 'TRANSPORTE', 'label': 'Transporte'},
    {'val': 'OTRO', 'label': 'Otro'},
  ];

  Future<void> _seleccionarArchivo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'pdf', 'png', 'jpeg'],
    );

    if (result != null) {
      setState(() {
        _archivoSeleccionado = File(result.files.single.path!);
      });
    }
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _enviando = true);
    
    final exito = await _api.enviarJustificacion(
      tareoId: widget.tareoId,
      motivo: _motivoSeleccionado,
      descripcion: _descController.text,
      archivo: _archivoSeleccionado,
    );

    setState(() => _enviando = false);
    
    if (exito) {
      widget.onSuccess();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al enviar")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Justificar ${widget.fechaStr}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 15),
            
            DropdownButtonFormField(
              value: _motivoSeleccionado,
              items: _opciones.map((o) => DropdownMenuItem(value: o['val'], child: Text(o['label']!))).toList(),
              onChanged: (v) => setState(() => _motivoSeleccionado = v.toString()),
              decoration: InputDecoration(labelText: "Motivo"),
            ),
            
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(labelText: "Descripción detallada"),
              maxLines: 3,
              validator: (v) => v!.isEmpty ? "Requerido" : null,
            ),
            SizedBox(height: 10),
            
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _seleccionarArchivo,
                  icon: Icon(Icons.attach_file),
                  label: Text("Adjuntar Evidencia"),
                ),
                SizedBox(width: 10),
                Expanded(child: Text(_archivoSeleccionado != null ? "Archivo seleccionado" : "Sin archivo", overflow: TextOverflow.ellipsis))
              ],
            ),
            SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                child: _enviando ? CircularProgressIndicator(color: Colors.white) : Text("ENVIAR JUSTIFICACIÓN"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
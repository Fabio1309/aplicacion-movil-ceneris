// lib/solicitud_horas_extra_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart'; // Lo crearemos en el siguiente paso

class SolicitudHorasExtraScreen extends StatefulWidget {
  const SolicitudHorasExtraScreen({super.key});

  @override
  _SolicitudHorasExtraScreenState createState() =>
      _SolicitudHorasExtraScreenState();
}

class _SolicitudHorasExtraScreenState extends State<SolicitudHorasExtraScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  DateTime? _selectedDate;
  final _horasController = TextEditingController();
  final _justificacionController = TextEditingController();
  bool _isLoading = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final success = await _apiService.solicitarHorasExtra(
          fecha: _selectedDate!,
          horas: double.parse(_horasController.text),
          justificacion: _justificacionController.text,
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Solicitud enviada con éxito.'),
                backgroundColor: Colors.green),
          );
          Navigator.of(context).pop();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error: No se pudo enviar la solicitud.'),
                backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar Horas Extra')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: <Widget>[
            // Selector de Fecha
            ListTile(
              title: Text(_selectedDate == null
                  ? 'Seleccionar fecha'
                  : 'Fecha: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context),
            ),
            if (_selectedDate ==
                null) // Muestra un error si no se selecciona fecha
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text('Por favor, seleccione una fecha.',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
              ),

            // Campo para Horas
            TextFormField(
              controller: _horasController,
              decoration: const InputDecoration(
                  labelText: 'Cantidad de Horas (ej: 2.5)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'Por favor, ingrese las horas.';
                if (double.tryParse(value) == null || double.parse(value) <= 0)
                  return 'Ingrese un número válido.';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Campo para Justificación
            TextFormField(
              controller: _justificacionController,
              decoration: const InputDecoration(
                  labelText: 'Justificación', border: OutlineInputBorder()),
              maxLines: 4,
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'La justificación es obligatoria.';
                return null;
              },
            ),
            const SizedBox(height: 32),

            // Botón de Envío
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submitRequest,
                    child: const Text('Enviar Solicitud'),
                  ),
          ],
        ),
      ),
    );
  }
}

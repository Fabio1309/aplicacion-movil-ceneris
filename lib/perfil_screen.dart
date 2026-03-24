// lib/perfil_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'app_colors.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  String nombre = 'Cargando...';
  String dni = 'Cargando...';
  String usuario = 'Cargando...';
  String area = 'Cargando...';
  String email = 'Cargando...';
  String telefono = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _cargarDatosDePerfil();
  }

  Future<void> _cargarDatosDePerfil() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nombre = prefs.getString('user_nombre') ?? 'No registrado';
      dni = prefs.getString('user_dni') ?? 'No registrado';
      usuario = prefs.getString('user_username') ?? 'No registrado';
      area = prefs.getString('user_area') ?? 'Sin Área';
      email = prefs.getString('user_email') ?? 'No registrado';
      telefono = prefs.getString('user_telefono') ?? 'No registrado';
    });
  }

  void _mostrarDialogoPassword() {
    showDialog(
      context: context,
      builder: (context) => const CambiarPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mi Perfil',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cabecera visual
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 30, top: 20),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person, size: 60, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Lista de Datos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildItemPerfil(Icons.account_circle_rounded, 'Usuario (Login)', usuario),
                  const Divider(height: 20),
                  
                  _buildItemPerfil(Icons.badge_rounded, 'DNI', dni),
                  const Divider(height: 20),
                  
                  _buildItemPerfil(
                    Icons.person_outline, 
                    'Nombre Completo', 
                    nombre,
                    onEdit: () {
                      showDialog(
                        context: context,
                        builder: (context) => const EditarNombreDialog(),
                      ).then((_) => _cargarDatosDePerfil());
                    }
                  ),
                  const Divider(height: 20),

                  // NUEVO: Correo Electrónico
                  _buildItemPerfil(
                    Icons.email_outlined, 
                    'Correo Electrónico', 
                    email,
                    onEdit: () {
                      showDialog(
                        context: context,
                        builder: (context) => const EditarEmailDialog(),
                      ).then((_) => _cargarDatosDePerfil());
                    }
                  ),
                  const Divider(height: 20),

                  // NUEVO: Teléfono
                  _buildItemPerfil(
                    Icons.phone_android_rounded, 
                    'Teléfono', 
                    telefono,
                    onEdit: () {
                      showDialog(
                        context: context,
                        builder: (context) => const EditarTelefonoDialog(),
                      ).then((_) => _cargarDatosDePerfil());
                    }
                  ),
                  const Divider(height: 20),
                  
                  _buildItemPerfil(Icons.work_outline, 'Área Asignada', area),
                  const Divider(height: 30),
                  
                  const SizedBox(height: 10),

                  // Botón de Cambiar Contraseña
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _mostrarDialogoPassword,
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text(
                        'Cambiar Contraseña',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemPerfil(IconData icon, String titulo, String valor, {VoidCallback? onEdit}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 28),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 22),
            onPressed: onEdit,
            tooltip: 'Editar $titulo',
          ),
      ],
    );
  }
}

// ======================================================================
// DIÁLOGO PARA EDITAR EMAIL
// ======================================================================
class EditarEmailDialog extends StatefulWidget {
  const EditarEmailDialog({super.key});

  @override
  State<EditarEmailDialog> createState() => _EditarEmailDialogState();
}

class _EditarEmailDialogState extends State<EditarEmailDialog> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _guardarEmail() async {
    final nuevoEmail = _emailController.text.trim();

    if (nuevoEmail.isEmpty || !nuevoEmail.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Ingrese un correo válido'), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      final Uri url = Uri.parse('https://ceneris-web-oror.onrender.com/api/actualizar-email/');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'email': nuevoEmail}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        await prefs.setString('user_email', data['nuevo_email']);
        if (mounted) Navigator.of(context).pop(); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Error al actualizar'), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Error de conexión'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Editar Correo', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress, // Activa el teclado con '@'
        decoration: const InputDecoration(
          labelText: 'Nuevo Correo Electrónico',
          prefixIcon: Icon(Icons.email_outlined),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(
                onPressed: _guardarEmail,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
      ],
    );
  }
}

// ======================================================================
// DIÁLOGO PARA EDITAR TELÉFONO
// ======================================================================
class EditarTelefonoDialog extends StatefulWidget {
  const EditarTelefonoDialog({super.key});

  @override
  State<EditarTelefonoDialog> createState() => _EditarTelefonoDialogState();
}

class _EditarTelefonoDialogState extends State<EditarTelefonoDialog> {
  final _telefonoController = TextEditingController();
  bool _isLoading = false;

  Future<void> _guardarTelefono() async {
    final nuevoTelefono = _telefonoController.text.trim();

    if (nuevoTelefono.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Ingrese un número de teléfono'), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      final Uri url = Uri.parse('https://ceneris-web-oror.onrender.com/api/actualizar-telefono/');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'telefono': nuevoTelefono}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        await prefs.setString('user_telefono', data['nuevo_telefono']);
        if (mounted) Navigator.of(context).pop(); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Error al actualizar'), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Error de conexión'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Editar Teléfono', style: TextStyle(fontWeight: FontWeight.bold)),
      content: TextField(
        controller: _telefonoController,
        keyboardType: TextInputType.phone, // Activa el teclado numérico
        maxLength: 9, // Opcional: Límite de 9 dígitos para Perú
        decoration: const InputDecoration(
          labelText: 'Nuevo Teléfono',
          prefixIcon: Icon(Icons.phone_android_rounded),
          counterText: '', // Oculta el contador de 0/9
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(
                onPressed: _guardarTelefono,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
      ],
    );
  }
}

// ======================================================================
// DIÁLOGO PARA EDITAR NOMBRE (El que ya teníamos)
// ======================================================================
class EditarNombreDialog extends StatefulWidget {
  const EditarNombreDialog({super.key});

  @override
  State<EditarNombreDialog> createState() => _EditarNombreDialogState();
}

class _EditarNombreDialogState extends State<EditarNombreDialog> {
  final _nombresController = TextEditingController();
  final _paternoController = TextEditingController();
  final _maternoController = TextEditingController();
  bool _isLoading = false;

  Future<void> _guardarNombre() async {
    final nombres = _nombresController.text.trim();
    final paterno = _paternoController.text.trim();
    final materno = _maternoController.text.trim();

    if (nombres.isEmpty || paterno.isEmpty || materno.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Llene todos los campos'), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      final Uri url = Uri.parse('https://ceneris-web-oror.onrender.com/api/actualizar-nombre/');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'nombres': nombres,
          'apellido_paterno': paterno,
          'apellido_materno': materno,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        await prefs.setString('user_nombre', data['nuevo_nombre_completo']);
        if (mounted) Navigator.of(context).pop(); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Error al actualizar'), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Error de conexión'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Editar Nombre', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nombresController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nombres')),
            const SizedBox(height: 10),
            TextField(controller: _paternoController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Apellido Paterno')),
            const SizedBox(height: 10),
            TextField(controller: _maternoController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Apellido Materno')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
        _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(onPressed: _guardarNombre, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text('Guardar', style: TextStyle(color: Colors.white))),
      ],
    );
  }
}

// ======================================================================
// DIÁLOGO PARA CAMBIAR CONTRASEÑA (El que ya teníamos)
// ======================================================================
class CambiarPasswordDialog extends StatefulWidget {
  const CambiarPasswordDialog({super.key});

  @override
  State<CambiarPasswordDialog> createState() => _CambiarPasswordDialogState();
}

class _CambiarPasswordDialogState extends State<CambiarPasswordDialog> {
  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  bool _isLoading = false;
  bool _ocultarActual = true;
  bool _ocultarNueva = true;

  Future<void> _cambiarPassword() async {
    final actual = _actualController.text.trim();
    final nueva = _nuevaController.text.trim();
    final confirmar = _confirmarController.text.trim();

    if (actual.isEmpty || nueva.isEmpty || confirmar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Llene todos los campos'), backgroundColor: Colors.red.shade700));
      return;
    }
    if (nueva != confirmar) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Las contraseñas no coinciden'), backgroundColor: Colors.red.shade700));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken') ?? '';
      final Uri url = Uri.parse('https://ceneris-web-oror.onrender.com/api/cambiar-password/');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', 
        },
        body: json.encode({
          'password_actual': actual,
          'nueva_password': nueva,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) Navigator.of(context).pop(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Contraseña cambiada con éxito'), backgroundColor: Colors.green.shade700));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Error al cambiar contraseña'), backgroundColor: Colors.red.shade700));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Error de conexión'), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Cambiar Contraseña', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _actualController, obscureText: _ocultarActual, decoration: InputDecoration(labelText: 'Contraseña Actual', suffixIcon: IconButton(icon: Icon(_ocultarActual ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _ocultarActual = !_ocultarActual)))),
            const SizedBox(height: 15),
            TextField(controller: _nuevaController, obscureText: _ocultarNueva, decoration: InputDecoration(labelText: 'Nueva Contraseña', suffixIcon: IconButton(icon: Icon(_ocultarNueva ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _ocultarNueva = !_ocultarNueva)))),
            const SizedBox(height: 15),
            TextField(controller: _confirmarController, obscureText: _ocultarNueva, decoration: const InputDecoration(labelText: 'Confirmar Nueva Contraseña')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
        _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton(onPressed: _cambiarPassword, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text('Guardar', style: TextStyle(color: Colors.white))),
      ],
    );
  }
}
/// Representa una fila de la lista de "usuarios autorizados" que el
/// backend expone en `/api/usuarios-autorizados/sync/` (CAV-182).
///
/// Deliberadamente NO contiene ningun dato de credenciales: solo
/// identifica quien esta autorizado y si sigue activo, para poder
/// validar accesos localmente cuando no hay conexion.
class AuthorizedUser {
  const AuthorizedUser({
    required this.dni,
    required this.username,
    required this.nombreCompleto,
    required this.activo,
    required this.actualizadoEn,
  });

  final String dni;
  final String username;
  final String nombreCompleto;
  final bool activo;
  final String actualizadoEn;

  factory AuthorizedUser.fromJson(Map<String, dynamic> json) {
    return AuthorizedUser(
      dni: json['dni'] as String,
      username: json['username'] as String,
      nombreCompleto: json['nombre_completo'] as String? ?? '',
      activo: json['activo'] as bool,
      actualizadoEn: json['actualizado_en'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'dni': dni,
        'username': username,
        'nombre_completo': nombreCompleto,
        'activo': activo,
        'actualizado_en': actualizadoEn,
      };
}

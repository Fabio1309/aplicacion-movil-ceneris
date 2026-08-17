import 'secure_credential_store.dart';
import 'user_sync_service.dart';

/// Motivo por el que un intento de login offline fue rechazado.
enum OfflineLoginFailureReason {
  /// La lista local de usuarios autorizados esta vencida (CAV-82): el
  /// dispositivo lleva demasiado tiempo sin conectarse a internet.
  authorizedListExpired,

  /// La contraseña ingresada no coincide con el hash guardado en este
  /// dispositivo (o nunca hubo un login online exitoso aqui).
  invalidCredentials,

  /// Las credenciales son correctas, pero el usuario ya no figura como
  /// activo/autorizado en la ultima lista sincronizada.
  notAuthorized,
}

class OfflineLoginResult {
  const OfflineLoginResult._({required this.success, this.failureReason});

  const OfflineLoginResult.success() : this._(success: true);

  const OfflineLoginResult.failure(OfflineLoginFailureReason reason)
      : this._(success: false, failureReason: reason);

  final bool success;
  final OfflineLoginFailureReason? failureReason;

  /// Mensaje listo para mostrar en pantalla.
  String get mensajeParaUsuario {
    switch (failureReason) {
      case OfflineLoginFailureReason.authorizedListExpired:
        return 'Tu dispositivo lleva demasiado tiempo sin conectarse a '
            'internet. Conéctate al menos una vez para poder ingresar '
            'sin conexión.';
      case OfflineLoginFailureReason.invalidCredentials:
        return 'Usuario o contraseña incorrectos.';
      case OfflineLoginFailureReason.notAuthorized:
        return 'Tu usuario ya no está autorizado. Contacta a Recursos '
            'Humanos.';
      case null:
        return '';
    }
  }
}

/// CAV-81 + CAV-82: valida un intento de login SIN conexión, usando
/// unicamente datos ya guardados en el dispositivo (CAV-180/181/182).
class OfflineLoginValidator {
  OfflineLoginValidator({
    required UserSyncService userSyncService,
    SecureCredentialStore? credentialStore,
  })  : _userSyncService = userSyncService,
        _credentialStore = credentialStore ?? SecureCredentialStore();

  final UserSyncService _userSyncService;
  final SecureCredentialStore _credentialStore;

  Future<OfflineLoginResult> validar({
    required String username,
    required String password,
  }) async {
    // CAV-82: primero se revisa la vigencia de la lista. Si esta vencida
    // se bloquea de inmediato, sin importar si la contraseña es correcta.
    if (await _userSyncService.listaAutorizadosVencida()) {
      return const OfflineLoginResult.failure(
        OfflineLoginFailureReason.authorizedListExpired,
      );
    }

    // CAV-81: la contraseña debe coincidir con el hash guardado la
    // ultima vez que este usuario se logueo bien en este dispositivo.
    final credencialValida = await _credentialStore.verifyCredential(
      username: username,
      password: password,
    );
    if (!credencialValida) {
      return const OfflineLoginResult.failure(
        OfflineLoginFailureReason.invalidCredentials,
      );
    }

    // El usuario debe seguir activo segun la ultima lista sincronizada
    // (por si fue desvinculado/desactivado desde la ultima sync).
    final autorizado = await _userSyncService.esUsuarioAutorizado(username);
    if (!autorizado) {
      return const OfflineLoginResult.failure(
        OfflineLoginFailureReason.notAuthorized,
      );
    }

    return const OfflineLoginResult.success();
  }
}

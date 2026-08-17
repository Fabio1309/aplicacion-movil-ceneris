import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/authorized_user.dart';
import 'secure_store.dart';

/// Se lanza cuando el checksum que envia el servidor no coincide con el
/// checksum recalculado localmente sobre los mismos datos (CAV-183):
/// la lista se descarta por completo, nunca se persiste a medias.
class IntegrityException implements Exception {
  IntegrityException(this.message);
  final String message;

  @override
  String toString() => 'IntegrityException: $message';
}

/// CAV-182 (cliente) + CAV-183: descarga de forma incremental la lista
/// de usuarios autorizados desde Django, verifica su integridad con un
/// checksum SHA-256, y la persiste cifrada en el dispositivo (CAV-180).
class UserSyncService {
  UserSyncService({
    required this.apiUrl,
    SecureStore? secureStore,
    http.Client? httpClient,
    Duration? authorizedListValidity,
  })  : _secureStore = secureStore ?? FlutterSecureCredentialStorage(),
        _httpClient = httpClient ?? http.Client(),
        authorizedListValidity =
            authorizedListValidity ?? defaultAuthorizedListValidity;

  static const _storedListKey = 'usuarios_autorizados_json';
  static const _storedChecksumKey = 'usuarios_autorizados_checksum';
  static const _lastSyncPrefsKey = 'usuarios_autorizados_last_sync';

  /// CAV-82: los trabajadores de esta app pueden quedar semanas sin
  /// señal (zonas mineras remotas), por eso la vigencia por defecto es
  /// larga (30 dias) en vez de horas/pocos dias. Es configurable por si
  /// una operacion puntual necesita una politica distinta.
  static const Duration defaultAuthorizedListValidity = Duration(days: 30);

  final String apiUrl;
  final SecureStore _secureStore;
  final http.Client _httpClient;
  final Duration authorizedListValidity;

  /// Recalcula el mismo checksum que genera el backend: SHA-256 sobre el
  /// JSON canonico (ordenado por dni, sin espacios) de la lista recibida.
  /// Debe coincidir byte a byte con la logica de
  /// `_calcular_checksum_usuarios` en `apps/api/views.py`.
  String _computeChecksum(List<dynamic> usuarios) {
    final normalizados = List<Map<String, dynamic>>.from(usuarios)
      ..sort((a, b) => (a['dni'] as String).compareTo(b['dni'] as String));
    final canonical = jsonEncode(normalizados);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Ejecuta una sincronizacion incremental (o completa, la primera vez)
  /// contra el backend, valida la integridad de la respuesta y persiste
  /// el resultado fusionado en el almacen cifrado.
  ///
  /// Lanza [IntegrityException] si el checksum no coincide: en ese caso
  /// la respuesta se descarta y NO se toca lo que ya habia almacenado.
  Future<List<AuthorizedUser>> sync({required String token}) async {
    final since = await _secureStore.read(key: _lastSyncPrefsKey);

    final uri = Uri.parse('$apiUrl/usuarios-autorizados/sync/').replace(
      queryParameters: since != null ? {'since': since} : null,
    );

    final response = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception(
        'Error al sincronizar usuarios autorizados (${response.statusCode}).',
      );
    }

    final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final usuariosJson = (body['usuarios'] as List).cast<Map<String, dynamic>>();
    final serverChecksum = body['checksum'] as String;
    final version = body['version'].toString();

    // --- CAV-183: verificacion de integridad de lo recibido ---
    final localChecksum = _computeChecksum(usuariosJson);
    if (localChecksum != serverChecksum) {
      throw IntegrityException(
        'El checksum de la lista de usuarios autorizados no coincide. '
        'Datos descartados por seguridad.',
      );
    }

    // Sincronizacion incremental: fusiona lo nuevo sobre lo ya guardado.
    final existentes = await _leerListaAlmacenada();
    final merged = <String, AuthorizedUser>{
      for (final u in existentes) u.dni: u,
    };
    for (final j in usuariosJson) {
      final u = AuthorizedUser.fromJson(j);
      merged[u.dni] = u;
    }
    final listaFinal = merged.values.toList();

    await _guardarLista(listaFinal);
    await _secureStore.write(key: _lastSyncPrefsKey, value: version);

    return listaFinal.where((u) => u.activo).toList();
  }

  Future<void> _guardarLista(List<AuthorizedUser> lista) async {
    final jsonList = lista.map((u) => u.toJson()).toList();
    final checksum = _computeChecksum(jsonList);
    await _secureStore.write(key: _storedListKey, value: jsonEncode(jsonList));
    await _secureStore.write(key: _storedChecksumKey, value: checksum);
  }

  /// Lee la lista persistida y vuelve a verificar su checksum contra lo
  /// guardado (CAV-183): protege contra manipulacion directa del
  /// almacenamiento local, no solo contra el canal de red.
  Future<List<AuthorizedUser>> _leerListaAlmacenada() async {
    final raw = await _secureStore.read(key: _storedListKey);
    if (raw == null) return [];

    final storedChecksum = await _secureStore.read(key: _storedChecksumKey);
    final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final recomputed = _computeChecksum(decoded);

    if (storedChecksum != null && recomputed != storedChecksum) {
      // El almacenamiento local fue alterado o esta corrupto: se descarta
      // por seguridad en vez de confiar en datos que no se pueden validar.
      return [];
    }

    return decoded.map(AuthorizedUser.fromJson).toList();
  }

  /// Lista local ya sincronizada, sin llamar a la red (para uso offline).
  Future<List<AuthorizedUser>> obtenerListaLocal() => _leerListaAlmacenada();

  /// Verifica localmente si [username] esta autorizado y activo, sin
  /// red. Se compara contra 'username' (no 'dni'): es el mismo campo
  /// que la app usa para loguearse (Django USERNAME_FIELD='username'),
  /// que no siempre coincide con el numero de DNI del trabajador.
  Future<bool> esUsuarioAutorizado(String username) async {
    final lista = await _leerListaAlmacenada();
    return lista.any((u) => u.username == username && u.activo);
  }

  /// Momento (segun el reloj del servidor) de la ultima sincronizacion
  /// exitosa, o `null` si el dispositivo nunca ha sincronizado.
  Future<DateTime?> ultimaSincronizacion() async {
    final raw = await _secureStore.read(key: _lastSyncPrefsKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// CAV-82: la lista local se considera "vencida" si nunca se
  /// sincronizo, o si la ultima sincronizacion exitosa fue hace mas de
  /// [authorizedListValidity]. Con la lista vencida, el login offline
  /// debe bloquearse aunque las credenciales sean correctas: obliga a
  /// que el dispositivo se conecte al menos una vez dentro de esa
  /// ventana para seguir confiando en los datos que tiene guardados.
  Future<bool> listaAutorizadosVencida() async {
    final ultima = await ultimaSincronizacion();
    if (ultima == null) return true;
    return DateTime.now().difference(ultima) > authorizedListValidity;
  }
}

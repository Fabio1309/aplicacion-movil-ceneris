import 'package:connectivity_plus/connectivity_plus.dart';

/// Envuelve la consulta de conectividad del dispositivo para poder
/// inyectarla en tests (login: los 3 casos de conectividad).
///
/// Distingue solo "sin señal en absoluto" (modo avion, datos apagados,
/// sin cobertura) de "hay alguna interfaz de red activa". No confirma
/// que esa red llegue realmente a internet -- eso solo se sabe al
/// intentar la conexion real contra el servidor.
class ConnectivityChecker {
  ConnectivityChecker({Future<List<ConnectivityResult>> Function()? checker})
      : _checker = checker ?? (() => Connectivity().checkConnectivity());

  final Future<List<ConnectivityResult>> Function() _checker;

  Future<bool> sinSenal() async {
    final resultados = await _checker();
    if (resultados.isEmpty) return true;
    return resultados.every((r) => r == ConnectivityResult.none);
  }
}

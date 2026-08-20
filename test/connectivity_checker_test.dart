import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ceneris/services/connectivity_checker.dart';

void main() {
  group('ConnectivityChecker (3 casos de conectividad del login)', () {
    test('sinSenal() es true cuando no hay ninguna interfaz activa '
        '(caso 3: modo avion / datos apagados / sin cobertura)', () async {
      final checker = ConnectivityChecker(
        checker: () async => [ConnectivityResult.none],
      );

      expect(await checker.sinSenal(), isTrue);
    });

    test('sinSenal() es true cuando la lista viene vacia', () async {
      final checker = ConnectivityChecker(checker: () async => []);

      expect(await checker.sinSenal(), isTrue);
    });

    test('sinSenal() es false cuando hay wifi (caso 1 o 2: hay señal, '
        'puede o no haber internet real)', () async {
      final checker = ConnectivityChecker(
        checker: () async => [ConnectivityResult.wifi],
      );

      expect(await checker.sinSenal(), isFalse);
    });

    test('sinSenal() es false cuando hay datos moviles', () async {
      final checker = ConnectivityChecker(
        checker: () async => [ConnectivityResult.mobile],
      );

      expect(await checker.sinSenal(), isFalse);
    });

    test('sinSenal() es false si al menos una interfaz no es none', () async {
      final checker = ConnectivityChecker(
        checker: () async => [ConnectivityResult.none, ConnectivityResult.wifi],
      );

      expect(await checker.sinSenal(), isFalse);
    });
  });
}

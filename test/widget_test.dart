// test/widget_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:ceneris/main.dart';
import 'package:ceneris/home_screen.dart'; // Importa HomeScreen para poder buscarla

void main() {
  // Smoke test de enrutamiento: cuando el usuario está logueado (dni + nombre +
  // area presentes), MyApp debe construir HomeScreen sin lanzar excepciones.
  // NOTA: no se afirma sobre el contenido interno de HomeScreen porque depende
  // de red / SharedPreferences / Firebase y arranca en estado de carga; esas
  // aserciones serían frágiles y requerirían mocks dedicados.
  testWidgets(
    'MyApp enruta a HomeScreen cuando el usuario está logueado',
    (WidgetTester tester) async {
      // Construimos la app en el estado "logueado".
      await tester.pumpWidget(
        const MyApp(
          isLoggedIn: true, // Simulamos que el usuario ya inició sesión
          dni: '12345678',
          nombre: 'Usuario de Prueba',
          area: 'Área de Prueba',
        ),
      );

      // Verificamos que la lógica de main.dart enrute a HomeScreen y que la
      // pantalla se construya correctamente.
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );
}

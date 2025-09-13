// test/widget_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:assistenciaceneris_app/main.dart';
import 'package:assistenciaceneris_app/home_screen.dart'; // Importa HomeScreen para poder buscarla

void main() {
  // Renombramos la prueba para que tenga sentido
  testWidgets(
    'HomeScreen muestra el botón de asistencia cuando el usuario está logueado',
    (WidgetTester tester) async {
      // 1. Construimos nuestra app en el estado "logueado"
      await tester.pumpWidget(
        const MyApp(
          isLoggedIn: true, // Simulamos que el usuario ya inició sesión
          dni: '12345678',
          nombre: 'Usuario de Prueba',
        ),
      );

      // 2. Verificamos que se esté mostrando la pantalla HomeScreen.
      // Esta es una buena práctica para asegurar que la lógica de main.dart funciona.
      expect(find.byType(HomeScreen), findsOneWidget);

      // 3. Verificamos que el título de la pantalla sea correcto.
      expect(find.text('Registro de Asistencia'), findsOneWidget);

      // 4. Verificamos que el botón principal exista en la pantalla.
      // En lugar de buscar el texto '0', buscamos el texto 'Marcar Asistencia'.
      expect(find.text('Marcar Asistencia'), findsOneWidget);
    },
  );
}

import 'dart:io';

import 'package:ceneris/device_utils.dart';
import 'package:ceneris/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cerrarSesion', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_logout_test_');
      Hive.init(tempDir.path);
      await Hive.openBox(SyncService.pendingBoxName);
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk(SyncService.pendingBoxName);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('conserva el unique_device_id', () async {
      // Si el logout borra el ID del dispositivo, al volver a entrar el app
      // genera uno nuevo y el candado "1 trabajador = 1 celular" del backend
      // bloquea el login hasta que RRHH libere el equipo.
      SharedPreferences.setMockInitialValues({
        deviceIdKey: 'device-uuid-original',
        'authToken': 'token',
        'user_nombre': 'Trabajador',
        'user_dni': '12345678',
        'cached_config': '{}',
      });

      await cerrarSesion();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(deviceIdKey), 'device-uuid-original');
    });

    test('borra los datos de sesion', () async {
      SharedPreferences.setMockInitialValues({
        deviceIdKey: 'device-uuid-original',
        'authToken': 'token',
        'user_nombre': 'Trabajador',
        'user_dni': '12345678',
      });

      await cerrarSesion();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('authToken'), isNull);
      expect(prefs.getString('user_nombre'), isNull);
      expect(prefs.getString('user_dni'), isNull);
    });

    test('NO toca la cola de asistencias pendientes', () async {
      // Son marcas ya hechas por el trabajador: cerrar sesion no puede
      // borrar planilla. Importa sobre todo el dia que se rote la clave de
      // firma del backend y todo el mundo tenga que volver a entrar.
      SharedPreferences.setMockInitialValues({
        deviceIdKey: 'device-uuid-original',
        'authToken': 'token',
      });

      final box = Hive.box(SyncService.pendingBoxName);
      await box.add({'tipo_marcacion': 'Entrada', 'client_uuid': 'uuid-1'});
      await box.add({'tipo_marcacion': 'Salida', 'client_uuid': 'uuid-2'});

      await cerrarSesion();

      expect(box.length, 2);
      expect(box.getAt(0)['client_uuid'], 'uuid-1');
    });
  });
}

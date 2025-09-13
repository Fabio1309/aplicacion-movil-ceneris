import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class SyncService {
  final Box _pendingBox = Hive.box('asistencias_pendientes');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSyncing = false;

  void startListening() {
    print("SyncService: Iniciando y escuchando cambios de conexión...");
    syncPendingAttendances();

    Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi)) {
        print(
          'SyncService: Conexión a internet detectada. Intentando sincronizar...',
        );
        syncPendingAttendances();
      } else {
        print('SyncService: Sin conexión a internet.');
      }
    });
  }

  Future<void> syncPendingAttendances() async {
    if (_isSyncing) {
      print('SyncService: Sincronización ya en progreso. Omitiendo.');
      return;
    }
    if (_pendingBox.isEmpty) {
      print('SyncService: No hay asistencias pendientes para sincronizar.');
      return;
    }

    _isSyncing = true;
    print(
      'SyncService: Se encontraron ${_pendingBox.length} asistencias pendientes. Bloqueando nuevas sincronizaciones.',
    );

    // 1. OBTENEMOS LAS UBICACIONES PERMITIDAS DESDE FIRESTORE
    List<Map<String, dynamic>> allowedLocations = [];
    try {
      final querySnapshot = await _firestore.collection('ubicaciones').get();
      allowedLocations = querySnapshot.docs.map((doc) => doc.data()).toList();
      print(
        "SyncService: Ubicaciones para validación cargadas: ${allowedLocations.length}",
      );
    } catch (e) {
      print(
        "SyncService: Error crítico al cargar ubicaciones. Se cancela la sincronización. $e",
      );
      _isSyncing = false;
      return;
    }

    final successfullyProcessedKeys = [];
    final keysToSync = _pendingBox.keys.toList();

    for (var key in keysToSync) {
      final attendanceData = Map<String, dynamic>.from(_pendingBox.get(key));
      final String createdAtString = attendanceData['createdAt'];
      final DateTime createdAtDate = DateTime.parse(createdAtString);

      try {
        // 2. VALIDAMOS LA UBICACIÓN DEL REGISTRO PENDIENTE
        bool isWithinAllowedLocation = false;
        String locationName = "Ubicación no verificada (sin conexión)";

        for (var location in allowedLocations) {
          final double lat = (location['latitud'] as num).toDouble();
          final double lon = (location['longitud'] as num).toDouble();
          final double rad = (location['radio'] as num? ?? 30.0).toDouble();
          double distance = Geolocator.distanceBetween(
            lat,
            lon,
            attendanceData['latitude'],
            attendanceData['longitude'],
          );
          if (distance <= rad) {
            isWithinAllowedLocation = true;
            locationName = location['nombre'];
            break;
          }
        }

        attendanceData.remove('createdAt');

        // 3. DECIDIMOS A DÓNDE ENVIAR EL REGISTRO
        if (isWithinAllowedLocation) {
          // Si la ubicación es VÁLIDA, lo enviamos a la colección de asistencias
          await _firestore.collection('asistencias').add({
            ...attendanceData,
            'locationName': locationName,
            'timestamp': Timestamp.fromDate(
              createdAtDate,
            ), // HORA REAL DE LA MARCACIÓN
            'syncedAt': FieldValue.serverTimestamp(),
            'status': 'success_synced',
          });
          print(
            'SyncService: Asistencia con clave $key VÁLIDA y sincronizada.',
          );
        } else {
          // Si la ubicación es INVÁLIDA, lo registramos como un intento de fraude
          await _firestore.collection('asistencias_fraudulentas').add({
            ...attendanceData,
            'reason': 'Ubicación fuera de rango (verificado en sincronización)',
            'timestamp': Timestamp.fromDate(createdAtDate),
            'syncedAt': FieldValue.serverTimestamp(),
          });
          print(
            'SyncService: Asistencia con clave $key INVÁLIDA y registrada como fraude.',
          );
        }

        successfullyProcessedKeys.add(key); // Marcamos para borrar de Hive
      } catch (e) {
        print('SyncService: Error al procesar la clave $key: $e');
      }
    }

    if (successfullyProcessedKeys.isNotEmpty) {
      await _pendingBox.deleteAll(successfullyProcessedKeys);
      print(
        'SyncService: ${successfullyProcessedKeys.length} registros procesados y eliminados de la caché.',
      );
    }

    _isSyncing = false;
    print('SyncService: Sincronización completada. Desbloqueando.');
  }
}

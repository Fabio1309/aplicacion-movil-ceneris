# Cómo probar los cambios de CAV-83

## 0. Requisito: JDK 21

```bash
winget install --id EclipseAdoptium.Temurin.21.JDK -e
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot"
flutter doctor -v
```

Después de esto `flutter build apk --debug` o `flutter run` deberían
compilar sin el error de Gradle 8.14 vs Java 25.

## 1. Automatizado (ya en verde, no requiere dispositivo)

```bash
flutter test
```

41 tests. Los que importan para este cambio:

```bash
flutter test test/trusted_clock_test.dart test/pending_attendance_queue_test.dart -r expanded
```

Cubren en aislamiento: que un 401 no borra la cola, que sin token no se
intenta, que un 4xx puntual no bloquea al resto, que atrasar/adelantar
el reloj del celular no cambia la hora registrada, y que un reinicio de
equipo invalida el ancla y cae a GPS.

## 2. Manual en un dispositivo — lo que confirma que sirve de verdad

Usa un emulador Android (más fácil de manipular reloj/GPS/conexión) o un
celular físico con `adb` conectado por USB.

```bash
flutter run
```

### 2.1 Sincronización que antes se perdía (el bug original)

1. Apaga el wifi/datos del dispositivo (o modo avión).
2. Marca una asistencia (Entrada). Debe aparecer "✅ Guardado Offline."
3. Revisa el historial de marcaciones: debe verse con badge naranja
   "Pendiente".
4. Reactiva la conexión.
5. **Antes del fix:** no pasaba nada, quedaba pendiente para siempre.
   **Ahora:** en unos segundos debe aparecer el snackbar verde
   "✅ 1 marcación(es) offline sincronizada(s)." y el historial la
   muestra como "Enviado".
6. Repite el ciclo 2–3 veces seguidas (offline → marcar → online) para
   confirmar que el candado `_isSyncing` se libera cada vez y no se
   traba en la segunda vuelta.

### 2.2 Sesión abierta offline → nunca se sincronizaba

1. Con conexión, cierra sesión.
2. Desactiva la conexión.
3. Inicia sesión con un usuario que ya haya iniciado sesión antes en
   ese equipo (requiere CAV-81/82 vigente). Debe entrar en modo
   offline.
4. Marca una asistencia offline.
5. Reactiva la conexión e inicia sesión de nuevo (online esta vez).
6. **Antes del fix:** como la sesión offline nunca tuvo `authToken`, el
   POST fallaba con 401 y el código viejo borraba igual la marcación:
   se perdía sin dejar rastro. **Ahora:** el login online dispara
   `syncPendingAttendances()` con el token recién obtenido y debe
   aparecer el snackbar de sincronización exitosa.

### 2.3 Antifraude de reloj — el caso que preguntaste

1. Con conexión, abre la app (esto ancla la hora del servidor).
2. Anota la hora real.
3. Desactiva la conexión.
4. Ve a Ajustes del sistema y **atrasa manualmente la hora del
   celular** 20–30 minutos (desactiva "fecha y hora automática"
   primero).
5. Vuelve a la app y marca asistencia.
6. Debe salir un snackbar naranja: "⏰ La hora de tu celular está
   desfasada X min. La marcación se registró con la hora real: HH:mm."
7. Revisa el registro guardado en Hive (o, tras sincronizar, lo que
   llegue a Django): el campo `timestamp`/`timestamp_utc` debe reflejar
   la hora **real**, no la que pusiste en el celular. Los campos
   `reloj_manipulado: true` y `desfase_reloj_segundos` deben viajar en
   el payload (revísalo con `read_network_requests` si usas el
   navegador embebido, o con un proxy tipo mitmproxy/Charles apuntando
   la app a él).
8. Vuelve a poner la hora automática antes de seguir probando otras
   cosas (o los timestamps de ahí en más quedarán raros).

Prueba también el caso inverso (adelantar el reloj) y confirma el mismo
comportamiento.

### 2.4 Reinicio de equipo durante el corte de señal

1. Con conexión, abre la app (ancla).
2. Desactiva la conexión.
3. Reinicia el emulador/celular (sin reconectar).
4. Marca una asistencia.
5. El ancla debe invalidarse (reinicio detectado por `BOOT_COUNT`) y la
   fuente de la hora debe caer a GPS. Si además atrasaste el reloj
   antes de reiniciar, debe seguir marcando `reloj_manipulado: true`
   porque GPS también es una fuente confiable.

### 2.5 Geocerca offline (antes se aceptaba cualquier ubicación)

1. Con conexión, dentro de una zona permitida, abre la app (esto
   cachea `_allowedLocations` en `cached_config`).
2. Desactiva la conexión.
3. Simula una ubicación GPS **fuera** de cualquier zona permitida
   (en el emulador: los tres puntos del panel lateral → Location, o
   `adb emu geo fix <lon> <lat>`).
4. Intenta marcar asistencia.
5. **Antes del fix:** se aceptaba igual (`"Offline"`, sin validar).
   **Ahora:** debe salir "❌ Estás fuera del área." y no debe
   encolarse nada.
6. Simula una ubicación dentro de una zona permitida y confirma que sí
   marca.

### 2.6 Fake GPS sigue bloqueado (no se tocó esa parte)

En el emulador, cualquier ubicación puesta manualmente cuenta como
"mocked" para `geolocator`. Confirma que sigue mostrando
"❌ Ubicación falsa detectada." y que, si hay conexión, se reporta a
Django con `is_fraud: true`.

## 3. Qué NO vas a poder probar sin tocar Django

Los campos nuevos de evidencia (`fuente_hora`, `reloj_manipulado`,
`hora_confiable`, etc., ver
[antifraude-marcaciones.md](antifraude-marcaciones.md)) hoy viajan en el
`POST /asistencias/registrar/`, pero si el serializer de Django no los
declara, los descarta en silencio — no da error, simplemente no los
guarda. Para confirmar que llegan bien desde el celular sin esperar a
que Django los acepte, la forma más rápida es interceptar la petición:

- Con el emulador: `adb logcat` no muestra el body HTTP por defecto,
  así que agrega temporalmente un `print(json.encode(data))` antes del
  `http.post` en `_postAttendanceToBackend` (o revisa el log de
  `debugPrint` de `SyncService`, que sí imprime resultados).
- O apunta `ApiConfig.useLocal = true` a un backend local Django con
  `print(request.data)` en la vista, para ver el payload completo tal
  cual llega.

# Antifraude de marcaciones offline

Qué manda la app móvil al registrar una asistencia y qué tiene que hacer
Django con eso.

## El problema

Una marcación hecha sin señal se guarda en el celular y se sube después.
La hora la ponía el celular, y el reloj del celular lo controla el
trabajador: bastaba con poner el teléfono en 8:25 cuando en realidad son
8:50 para "llegar temprano". Lo mismo con la ubicación: sin conexión la
app aceptaba cualquier coordenada, así que el modo avión servía para
marcar desde la casa.

## Cómo se resuelve del lado de la app

**Hora.** Cada respuesta del servidor trae su hora en la cabecera HTTP
`Date`. La app la guarda junto al valor del reloj *monotónico* del
equipo (`SystemClock.elapsedRealtime()` en Android, `CLOCK_MONOTONIC` en
iOS), que cuenta desde el arranque y **no se puede cambiar desde
Ajustes**. Después, ya sin conexión:

```
hora_real = hora_servidor_anclada + (monotónico_ahora − monotónico_anclado)
```

Cambiar la hora del celular no mueve ese cálculo. El único evento que lo
invalida es reiniciar el equipo (el monotónico vuelve a cero); se detecta
con `Settings.Global.BOOT_COUNT` y, en ese caso, la app cae a la hora del
fix de GPS (que viene de los satélites) y, si tampoco hay, al reloj del
celular — pero marcando el registro como no confiable.

**Ubicación.** La geocerca ahora se valida igual con y sin conexión,
contra las zonas ya cacheadas en el dispositivo.

## Campos que recibe `POST /asistencias/registrar/`

Los que ya existían no cambian. Estos son los nuevos:

| Campo | Tipo | Para qué sirve |
|---|---|---|
| `timestamp_utc` | ISO-8601 con `Z` | **La hora buena.** Inmune a cambios de zona horaria. Conviene migrar a este campo y dejar de usar `timestamp`. |
| `timestamp_dispositivo` | ISO-8601 local | Lo que marcaba el reloj del celular. Solo como evidencia. |
| `fuente_hora` | `servidor_monotonico` \| `gps` \| `dispositivo` | De dónde salió la hora. `dispositivo` = no verificable. |
| `hora_confiable` | bool | `false` cuando `fuente_hora` es `dispositivo`. |
| `desfase_reloj_segundos` | int | `reloj_celular − hora_real`. Negativo = el celular va atrasado (el caso del que atrasa el reloj). |
| `reloj_manipulado` | bool | El desfase supera 2 minutos y la hora viene de fuente confiable. |
| `zona_horaria_cambiada` | bool | Cambió la zona horaria desde el último anclaje. |
| `zona_horaria_offset_minutos` | int | Offset del equipo al marcar. |
| `hora_automatica_activa` | bool | Solo Android: si la fecha/hora automática está activa. |
| `antiguedad_ancla_horas` | int | Hace cuántas horas se ancló contra el servidor. |
| `registrado_offline` | bool | La marcación se hizo sin conexión y se subió después. |
| `ubicacion_verificada` | bool | `false` solo si el equipo no tenía zonas cacheadas contra qué validar. |

## Qué falta hacer en Django

Sin esto, la evidencia llega y se descarta en silencio (DRF ignora los
campos que el serializer no declara), y el antifraude queda a medias:

1. **Aceptar los campos nuevos** en el serializer de asistencias y
   persistirlos (o al menos `timestamp_utc`, `fuente_hora`,
   `reloj_manipulado` y `desfase_reloj_segundos`).
2. **Usar `timestamp_utc`** como hora oficial de la marcación en vez de
   `timestamp`.
3. **Marcar para revisión** de RR.HH. toda asistencia con
   `reloj_manipulado = true`, `hora_confiable = false`,
   `zona_horaria_cambiada = true` o `ubicacion_verificada = false`.
   Recomendación: registrarlas igual (no rechazarlas), pero señaladas —
   una marcación rechazada por el servidor se queda pendiente en el
   celular y el trabajador no tiene cómo corregirla.
4. **Validar la geocerca del lado del servidor** con `latitud`/`longitud`,
   sin confiar en `nombre_ubicacion`, que lo calcula el cliente.
5. **Responder `409`** cuando llegue una marcación que ya estaba
   registrada: la app la da por sincronizada y la saca de la cola.
   Cualquier `4xx` sin ese significado deja el registro pendiente.

## Lo que este diseño NO cubre

- Un equipo con **root** puede alterar cualquier cosa, incluido el
  almacenamiento cifrado.
- Un dispositivo **recién instalado que nunca se conectó** no tiene ancla
  ni zonas cacheadas: sus marcaciones llegan con `hora_confiable: false`
  y `ubicacion_verificada: false`. Es el caso que debe revisar RR.HH.
- La hora del GPS es confiable cuando el fix viene de satélites, pero en
  Android puede provenir del proveedor fusionado (derivado del reloj del
  sistema). Por eso `fuente_hora: gps` vale menos que
  `servidor_monotonico`.

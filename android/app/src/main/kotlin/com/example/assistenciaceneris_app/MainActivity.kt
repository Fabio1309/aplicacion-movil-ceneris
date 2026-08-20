package com.example.assistenciaceneris_app

import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * CAV-83 (antifraude de reloj): expone a Dart el reloj MONOTÓNICO del
 * dispositivo.
 *
 * `SystemClock.elapsedRealtime()` cuenta los milisegundos transcurridos
 * desde que el equipo arrancó (incluido el tiempo en suspensión) y NO se
 * puede modificar desde Ajustes: cambiar la fecha/hora del teléfono no
 * lo altera. Eso permite calcular la hora real aunque el trabajador
 * atrase el reloj del celular para aparentar que marcó más temprano.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "ceneris/device_clock"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Milisegundos desde el arranque del equipo.
                    "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())

                    // ¿La fecha/hora está en modo automático (por red)?
                    // Tenerlo en manual no prueba fraude, pero es una
                    // señal más para que RR.HH. revise el registro.
                    "autoTimeEnabled" -> result.success(isAutoTimeEnabled())

                    // Nº de arranques del equipo desde que se configuró.
                    // Sirve como "id de sesión de arranque": si cambia,
                    // el equipo se reinició y el reloj monotónico volvió
                    // a cero, así que el ancla de hora ya no vale.
                    "bootCount" -> result.success(bootCount())

                    else -> result.notImplemented()
                }
            }
    }

    private fun isAutoTimeEnabled(): Boolean? =
        globalSetting(Settings.Global.AUTO_TIME)?.let { it == 1 }

    /** `Settings.Global.BOOT_COUNT` existe desde Android 7 (API 24). */
    private fun bootCount(): Int? = globalSetting("boot_count")

    private fun globalSetting(name: String): Int? {
        return try {
            Settings.Global.getInt(contentResolver, name)
        } catch (e: Settings.SettingNotFoundException) {
            null
        } catch (e: Exception) {
            null
        }
    }
}

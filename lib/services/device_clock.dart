import 'package:flutter/services.dart';

/// CAV-83 (antifraude de reloj): acceso al reloj monotónico del equipo.
///
/// Es la única fuente de tiempo del dispositivo que el usuario NO puede
/// manipular desde Ajustes: cuenta desde el arranque, no desde una
/// fecha. Cambiar la hora del celular no la mueve.
///
/// Se implementa nativamente en `MainActivity.kt` (Android) y
/// `AppDelegate.swift` (iOS).
class DeviceClock {
  const DeviceClock({MethodChannel channel = _defaultChannel})
      : _channel = channel;

  static const _defaultChannel = MethodChannel('ceneris/device_clock');

  final MethodChannel _channel;

  /// Tiempo transcurrido desde que arrancó el equipo, o `null` si la
  /// plataforma no lo soporta (por ejemplo, en tests o en escritorio).
  Future<Duration?> elapsedRealtime() async {
    try {
      final millis = await _channel.invokeMethod<int>('elapsedRealtime');
      if (millis == null) return null;
      return Duration(milliseconds: millis);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// ¿El equipo tiene la fecha/hora en modo automático? `null` cuando no
  /// se puede saber (iOS no lo expone).
  Future<bool?> horaAutomaticaActiva() async {
    try {
      return await _channel.invokeMethod<bool>('autoTimeEnabled');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Número de arranques del equipo (Android 7+). Funciona como "id de
  /// sesión de arranque": si cambia, hubo un reinicio y el reloj
  /// monotónico se reseteó. `null` si la plataforma no lo expone.
  Future<int?> bootCount() async {
    try {
      return await _channel.invokeMethod<int>('bootCount');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

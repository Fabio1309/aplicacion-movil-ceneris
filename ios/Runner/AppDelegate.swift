import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// CAV-83 (antifraude de reloj): equivalente iOS de
  /// `SystemClock.elapsedRealtime()` de Android.
  ///
  /// En Apple, `CLOCK_MONOTONIC` cuenta desde el arranque del equipo y
  /// sigue avanzando mientras el dispositivo duerme, y no se ve afectado
  /// por cambios de fecha/hora en Ajustes.
  private static let clockChannelName = "ceneris/device_clock"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: AppDelegate.clockChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "elapsedRealtime":
          result(AppDelegate.elapsedRealtimeMillis())
        case "autoTimeEnabled":
          // iOS no expone si "Ajustar automáticamente" está activo.
          result(nil)
        case "bootCount":
          // iOS no expone un contador de arranques. La detección de
          // reinicio queda a cargo del reloj monotónico.
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func elapsedRealtimeMillis() -> Int64 {
    var ts = timespec()
    guard clock_gettime(CLOCK_MONOTONIC, &ts) == 0 else { return 0 }
    return Int64(ts.tv_sec) * 1000 + Int64(ts.tv_nsec) / 1_000_000
  }
}

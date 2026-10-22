import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  
  private var lastTelemetryData: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    // Register method channels for CarPlay / platform telemetry projection
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channelNames = ["com.motologger.app/car_projection", "com.motologger.app/car_telemetry"]
    for name in channelNames {
      let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "updateTelemetry":
          if let args = call.arguments as? [String: Any] {
            self?.lastTelemetryData = args
            result(true)
          } else {
            result(false)
          }
        case "startRecordingService", "stopRecordingService":
          // Handled via iOS background modes (location / bluetooth-central)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  func getLatestTelemetry() -> [String: Any]? {
    return lastTelemetryData
  }
}

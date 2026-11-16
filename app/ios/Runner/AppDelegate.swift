import CarPlay
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var lastTelemetryData: [String: Any]?
  private var carProjectionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channelNames = ["com.motologger.app/car_projection", "com.motologger.app/car_telemetry"]

    for name in channelNames {
      let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
      if name == "com.motologger.app/car_projection" {
        self.carProjectionChannel = channel
      }

      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "updateTelemetry":
          if let args = call.arguments as? [String: Any] {
            self?.lastTelemetryData = args
            if #available(iOS 14.0, *) {
              CarPlayManager.shared.update(args)
            }
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

    if #available(iOS 14.0, *) {
      CarPlayManager.shared.onTareZeroRequested = { [weak self] in
        DispatchQueue.main.async {
          self?.carProjectionChannel?.invokeMethod("tareZero", arguments: nil)
        }
      }
    }
  }

  func getLatestTelemetry() -> [String: Any]? {
    return lastTelemetryData
  }
}

// MARK: - Apple CarPlay Scene Delegate

@available(iOS 14.0, *)
public class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

  private var interfaceController: CPInterfaceController?

  public func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    CarPlayManager.shared.attachInterfaceController(interfaceController)
  }

  public func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    CarPlayManager.shared.detachInterfaceController()
    self.interfaceController = nil
  }
}

// MARK: - CarPlay Telemetry Projection Manager

@available(iOS 14.0, *)
public class CarPlayManager {
  public static let shared = CarPlayManager()

  private init() {}

  private weak var interfaceController: CPInterfaceController?
  private var currentTemplate: CPInformationTemplate?
  private var latestTelemetry: [String: Any]?
  public var onTareZeroRequested: (() -> Void)?

  public func attachInterfaceController(_ controller: CPInterfaceController) {
    self.interfaceController = controller
    renderTemplate()
  }

  public func detachInterfaceController() {
    self.interfaceController = nil
    self.currentTemplate = nil
  }

  public func update(_ telemetry: [String: Any]) {
    self.latestTelemetry = telemetry
    DispatchQueue.main.async { [weak self] in
      self?.renderTemplate()
    }
  }

  public func requestTareZero() {
    onTareZeroRequested?()
  }

  private func formatLapTime(ms: Int64) -> String {
    if ms <= 0 { return "0:00.0" }
    let totalSec = ms / 1000
    let min = totalSec / 60
    let sec = totalSec % 60
    let tenths = (ms % 1000) / 100
    return String(format: "%d:%02d.%d", min, sec, tenths)
  }

  private func buildInformationItems() -> [CPInformationItem] {
    let t = latestTelemetry ?? [:]
    let isConnected = (t["isConnected"] as? Bool) ?? false
    let isRecording = (t["isRecording"] as? Bool) ?? false

    // 1. Lean Angle row
    let leanStr: String
    if isConnected, let lean = (t["leanAngleDeg"] as? NSNumber)?.doubleValue {
      leanStr = String(format: "%.1f°", lean)
    } else {
      leanStr = "—"
    }

    let maxLeftStr: String
    if let maxLeft = (t["maxLeanLeft"] as? NSNumber)?.doubleValue, maxLeft < 0.0 {
      maxLeftStr = String(format: "%.1f°", maxLeft)
    } else {
      maxLeftStr = "—"
    }

    let maxRightStr: String
    if let maxRight = (t["maxLeanRight"] as? NSNumber)?.doubleValue, maxRight > 0.0 {
      maxRightStr = String(format: "+%.1f°", maxRight)
    } else {
      maxRightStr = "—"
    }

    let leanItem = CPInformationItem(
      title: "NÁKLON",
      detail: "Aktuální: \(leanStr) | Max vlevo: \(maxLeftStr) | Max vpravo: \(maxRightStr)"
    )

    // 2. Powertrain & Gear row (Strict Truthful Telemetry: gear >= 0, 0 is Neutral, <0 or null is em-dash)
    let speedVal = (t["speedKmh"] as? NSNumber)?.intValue
    let speedStr: String
    if let s = speedVal, (isConnected || s > 0), s >= 0 {
      speedStr = "\(s) km/h"
    } else {
      speedStr = "—"
    }

    let gearVal = (t["gear"] as? NSNumber)?.intValue
    let gearStr: String
    if isConnected, let g = gearVal, g >= 0 {
      gearStr = (g == 0) ? "N" : "\(g)"
    } else {
      gearStr = "—"
    }

    let rpmVal = (t["engineRpm"] as? NSNumber)?.intValue
    let rpmStr: String
    if isConnected, let rpm = rpmVal, rpm > 0 {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      let formattedRpm = formatter.string(from: NSNumber(value: rpm)) ?? "\(rpm)"
      rpmStr = "\(formattedRpm) ot/min"
    } else {
      rpmStr = "—"
    }

    let powertrainItem = CPInformationItem(
      title: "RYCHLOST & POHON",
      detail: "Rychlost: \(speedStr) | Převod: \(gearStr) | Otáčky: \(rpmStr)"
    )

    // 3. Status & Lap timer row
    let statusText: String
    if isRecording {
      let lap = (t["currentLap"] as? NSNumber)?.intValue ?? 1
      let lapElapsedMs = (t["lapElapsedMs"] as? NSNumber)?.int64Value ?? 0
      let lapTimeStr = formatLapTime(ms: lapElapsedMs)
      let deltaStr: String
      if let delta = (t["deltaSeconds"] as? NSNumber)?.doubleValue {
        let sign = delta > 0 ? "+" : ""
        deltaStr = String(format: " | Delta: %@%.2fs", sign, delta)
      } else {
        deltaStr = ""
      }
      statusText = "Záznam běží · Kolo \(lap) (\(lapTimeStr)\(deltaStr))"
    } else {
      let connStr = isConnected ? "Jednotka připojena" : "Jednotka odpojena"
      let coolantVal = (t["coolantTempC"] as? NSNumber)?.intValue
      let tempStr: String
      if isConnected, let temp = coolantVal, temp > 0 {
        tempStr = " | Teplota vody: \(temp)°C"
      } else {
        tempStr = ""
      }
      statusText = "\(connStr)\(tempStr)"
    }

    let statusItem = CPInformationItem(
      title: "STAV JÍZDY",
      detail: statusText
    )

    return [leanItem, powertrainItem, statusItem]
  }

  private func renderTemplate() {
    guard let controller = interfaceController else { return }
    let items = buildInformationItems()

    if let infoTemplate = currentTemplate {
      infoTemplate.items = items
    } else {
      let tareAction = CPTextButton(
        title: "VYNULOVAT NÁKLON (TARE)",
        textStyle: .confirm
      ) { [weak self] _ in
        self?.requestTareZero()
      }

      let infoTemplate = CPInformationTemplate(
        title: "MotoLogger Telemetrie",
        layout: .leading,
        items: items,
        actions: [tareAction]
      )
      currentTemplate = infoTemplate
      controller.setRootTemplate(infoTemplate, animated: false, completion: nil)
    }
  }
}

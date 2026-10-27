import Flutter
import UIKit
import UserNotifications
import Darwin

public class NotifiablePlugin: NSObject, FlutterPlugin, FlutterApplicationDelegate {
  private let tokenStore = PushTokenStore()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NotifiablePlugin()
    let channel = FlutterMethodChannel(
      name: "sh.notifiable/notifiable",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permissionStatus":
      permissionStatus(result: result)
    case "requestPermission":
      requestPermission(result: result)
    case "getToken":
      token(result: result)
    case "registrationError":
      result(tokenStore.failureMessage())
    case "deviceProfile":
      result(deviceProfile())
    case "openUrl":
      if let url = call.arguments as? String, let parsed = URL(string: url) {
        DispatchQueue.main.async {
          UIApplication.shared.open(parsed)
        }
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    tokenStore.set(deviceToken: deviceToken)
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    tokenStore.fail(error.localizedDescription)
  }

  private func permissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        result(Self.map(settings.authorizationStatus))
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let current = Self.map(settings.authorizationStatus)

      if current == "denied" {
        DispatchQueue.main.async {
          self.openNotificationSettings()
          result("denied")
        }
        return
      }

      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        _, _ in
        UNUserNotificationCenter.current().getNotificationSettings { updated in
          let status = Self.map(updated.authorizationStatus)

          DispatchQueue.main.async {
            if status == "granted" {
              self.tokenStore.prepareForRegistration()
              UIApplication.shared.registerForRemoteNotifications()
            }
            result(status)
          }
        }
      }
    }
  }

  private func openNotificationSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      return
    }
    UIApplication.shared.open(url)
  }

  private func token(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status = Self.map(settings.authorizationStatus)

      if status == "granted" {
        DispatchQueue.main.async {
          self.tokenStore.prepareForRegistration()
          UIApplication.shared.registerForRemoteNotifications()
        }
      }

      DispatchQueue.global().async {
        let value = self.tokenStore.wait(timeout: status == "granted" ? 10 : 0)
        DispatchQueue.main.async {
          result(value)
        }
      }
    }
  }

  private func deviceProfile() -> [String: Any] {
    var system = utsname()
    uname(&system)
    let model = withUnsafePointer(to: &system.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let simulator: Bool
    #if targetEnvironment(simulator)
      simulator = true
    #else
      simulator = false
    #endif

    return [
      "osVersion": UIDevice.current.systemVersion,
      "locale": Locale.current.identifier,
      "timezone": TimeZone.current.identifier,
      "model": model,
      "manufacturer": "Apple",
      "appVersion": version ?? "",
      "applicationId": Bundle.main.bundleIdentifier ?? "",
      "isSimulator": simulator,
    ]
  }

  private static func map(_ status: UNAuthorizationStatus) -> String {
    if #available(iOS 14.0, *), status == .ephemeral {
      return "granted"
    }

    switch status {
    case .authorized, .provisional:
      return "granted"
    case .denied:
      return "denied"
    default:
      return "not_determined"
    }
  }
}

final class PushTokenStore {
  private let lock = NSLock()
  private var token: String?
  private var failed = false
  private var failure: String?

  func set(deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    lock.lock()
    token = hex
    failed = false
    failure = nil
    lock.unlock()
  }

  func fail(_ message: String) {
    lock.lock()
    failed = true
    failure = message
    lock.unlock()
  }

  func prepareForRegistration() {
    lock.lock()
    failed = false
    failure = nil
    lock.unlock()
  }

  func failureMessage() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return failure
  }

  func wait(timeout: TimeInterval) -> String? {
    let deadline = Date().addingTimeInterval(timeout)

    while true {
      if let token = read() {
        return token
      }

      if didFail() || Date() >= deadline {
        return read()
      }

      Thread.sleep(forTimeInterval: 0.05)
    }
  }

  private func read() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return token
  }

  private func didFail() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return failed
  }
}

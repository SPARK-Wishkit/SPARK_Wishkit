import Flutter
import UIKit
import UserNotifications

enum NativeShareBridge {
  static let channelName = "com.softstudio.wishlist/share"
  static let takePending = "takePendingShareText"
  static let sharedText = "sharedText"
  static let appGroupId = "group.com.softstudio.wishlist"
  static let shareSchemePrefix = "ShareMedia-com.softstudio.wishlist"

  static var channel: FlutterMethodChannel?
  static var pendingText: String?

  static func consumeAppGroupShare() -> String? {
    let defaults = UserDefaults(suiteName: appGroupId)
    let message = defaults?.string(forKey: "ShareMessageKey")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var parts: [String] = []
    if let message, !message.isEmpty {
      parts.append(message)
    }
    if let data = defaults?.data(forKey: "ShareKey"),
       let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      for item in items {
        if let path = item["path"] as? String {
          let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty, !parts.contains(trimmed) {
            parts.append(trimmed)
          }
        }
      }
    }
    defaults?.removeObject(forKey: "ShareKey")
    defaults?.removeObject(forKey: "ShareMessageKey")
    let text = parts.joined(separator: "\n")
    return text.isEmpty ? nil : text
  }

  static func handleIncoming(url: URL) -> Bool {
    guard url.absoluteString.hasPrefix(shareSchemePrefix) else { return false }
    deliver(consumeAppGroupShare())
    return true
  }

  static func deliver(_ text: String?) {
    guard let text, !text.isEmpty else { return }
    if let channel {
      channel.invokeMethod(sharedText, arguments: text)
    } else {
      pendingText = text
    }
  }

  static func bind(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == takePending {
        let text = pendingText
        pendingText = nil
        result(text)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    if let pendingText {
      self.pendingText = nil
      channel.invokeMethod(sharedText, arguments: pendingText)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    if let url = launchOptions?[.url] as? URL {
      _ = NativeShareBridge.handleIncoming(url: url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if NativeShareBridge.handleIncoming(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    NativeShareBridge.bind(to: engineBridge.applicationRegistrar.messenger())
  }
}

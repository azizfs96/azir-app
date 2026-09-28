import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Kick off APNs registration so iOS issues a device token. firebase_messaging
    // does not always call this itself, and without it getToken() waits forever on
    // an APNS token that never arrives. Firebase's AppDelegate swizzling captures
    // the token from didRegisterForRemoteNotificationsWithDeviceToken.
    application.registerForRemoteNotifications()

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Baseline: don't interrupt other audio (music, calls, etc.)
    setAmbientAudioSession()

    // Clear stale badge on launch
    application.applicationIconBadgeNumber = 0

    // Set up FCM (Firebase is initialized in Flutter main.dart)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { granted, error in
          if let error = error {
            print("❌ Notification permission error: \(error.localizedDescription)")
          } else {
            print("✅ Notification permission granted: \(granted)")
          }
        }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)

    // MethodChannel so Flutter can restore the audio session after the
    // camera plugin overrides it during CameraController.initialize().
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.boomerang/audio_session",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setAmbient":
        self?.setAmbientAudioSession()
        result(true)
      case "deactivate":
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        self?.setAmbientAudioSession()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Forward APNs token to FCM for push notifications.
  override func application(_ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    if #available(iOS 10.0, *) {
      print("✅ APNs token registered: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
    }
  }
  
  // Handle APNs registration failure
  override func application(_ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    application.applicationIconBadgeNumber = 0
  }

  // Handle notification when app is in foreground — don't update badge since
  // the user is already in the app; in-app UI handles unread state.
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .sound]])
    } else {
      completionHandler([[.alert, .sound]])
    }
  }
  
  // Handle notification tap — clear badge since user is entering the app
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    UIApplication.shared.applicationIconBadgeNumber = 0
    completionHandler()
  }

  /// Sets AVAudioSession to .ambient so the app mixes with background music
  /// and never interrupts phone calls.
  private func setAmbientAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.ambient)
    } catch {
      print("Audio session error: \(error.localizedDescription)")
    }
  }
}

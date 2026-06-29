import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 1. เพิ่มโค้ดส่วนนี้เพื่อดึงค่า Key จาก Info.plist
    //    (ใช้ "Maps_API_KEY" ให้ตรงกับที่คุณตั้งไว้)
    guard let googleMapsAPIKey = Bundle.main.object(forInfoDictionaryKey: "Maps_API_KEY") as? String else {
        fatalError("Google Maps API Key not found in Info.plist")
    }

    // 2. ใช้ตัวแปรที่ดึงมาได้ในบรรทัดนี้
    GMSServices.provideAPIKey(googleMapsAPIKey)

    // 🔔 ขอสิทธิ์แจ้งเตือน iOS
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
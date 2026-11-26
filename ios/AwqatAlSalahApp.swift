import SwiftUI
import UserNotifications

@main
struct AwqatAlSalahApp: App {
    @StateObject private var notifications = PrayerNotificationManager()
    init() { UNUserNotificationCenter.current().delegate = NotificationDelegate.shared }
    var body: some Scene {
        WindowGroup { ContentView(notifications: notifications).preferredColorScheme(.dark) }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

import Foundation
import UserNotifications
import PortWatcherCore

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let manager = PortNotificationManager()

    // Must run after the app has finished launching; calling it from App.init()
    // is silently ignored by macOS.
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("PortWatcher notification authorization failed: \(error.localizedDescription)") }
            else { NSLog("PortWatcher notification authorization granted=\(granted)") }
        }
    }

    func attach(to viewModel: PortListViewModel) {
        viewModel.onChanges = { [manager] changes in
            guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
            manager.handle(changes)
        }
    }

    // Show banners even while the panel (our only UI) is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

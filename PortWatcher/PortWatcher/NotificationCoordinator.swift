import Foundation
import UserNotifications
import PortWatcherCore

@MainActor
final class NotificationCoordinator {
    private let manager = PortNotificationManager()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("Notification authorization failed: \(error.localizedDescription)") }
            else if !granted { NSLog("Notification authorization denied by user") }
        }
    }

    func attach(to viewModel: PortListViewModel) {
        viewModel.onChanges = { [manager] changes in
            guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
            manager.handle(changes)
        }
    }
}

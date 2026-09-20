import SwiftUI
import PortWatcherCore

@main
struct PortWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Port Watcher", systemImage: "network") {
            PortListView(viewModel: appDelegate.viewModel)
                .frame(width: 600, height: 440)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PortListViewModel()
    private let notifications = NotificationCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifications.attach(to: viewModel)
        notifications.requestAuthorization()
    }
}

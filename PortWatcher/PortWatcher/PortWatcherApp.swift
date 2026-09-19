import SwiftUI
import PortWatcherCore

@main
struct PortWatcherApp: App {
    @State private var viewModel = PortListViewModel()
    @State private var notifications = NotificationCoordinator()

    init() {
        let viewModel = PortListViewModel()
        let notifications = NotificationCoordinator()
        notifications.requestAuthorization()
        notifications.attach(to: viewModel)
        _viewModel = State(initialValue: viewModel)
        _notifications = State(initialValue: notifications)
    }

    var body: some Scene {
        MenuBarExtra("Port Watcher", systemImage: "network") {
            PortListView(viewModel: viewModel)
                .frame(width: 600, height: 440)
        }
        .menuBarExtraStyle(.window)
    }
}

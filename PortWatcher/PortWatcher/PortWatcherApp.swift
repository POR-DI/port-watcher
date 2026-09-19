import SwiftUI
import PortWatcherCore

@main
struct PortWatcherApp: App {
    @State private var viewModel = PortListViewModel()

    var body: some Scene {
        MenuBarExtra("Port Watcher", systemImage: "network") {
            PortListView(viewModel: viewModel)
                .frame(width: 600, height: 440)
        }
        .menuBarExtraStyle(.window)
    }
}

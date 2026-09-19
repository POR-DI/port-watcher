import SwiftUI
import PortWatcherCore

@main
struct PortWatcherApp: App {
    var body: some Scene {
        MenuBarExtra("Port Watcher", systemImage: "network") {
            Text("PortWatcherCore linked: \(LsofOutputParser.parse("").count) entries")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}

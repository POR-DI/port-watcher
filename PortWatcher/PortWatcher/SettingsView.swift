import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 3
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var notificationsAllowed = true
    var onDone: () -> Void

    var body: some View {
        Form {
            Stepper(value: $refreshInterval, in: 1...30, step: 1) {
                Text("Refresh every \(Int(refreshInterval)) s")
            }
            Toggle("Notify when ports open or close", isOn: $notificationsEnabled)
            if !notificationsAllowed {
                // Ad-hoc signed builds get UNErrorDomain 1 "not allowed" from macOS.
                Text("macOS does not allow notifications for this build. Sign the app with an Apple ID team in Xcode to enable them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Done") { onDone() }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 300)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .notDetermined
        }
    }
}

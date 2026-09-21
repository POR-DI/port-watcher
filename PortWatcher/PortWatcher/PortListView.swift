import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PortWatcherCore

struct PortListView: View {
    @Bindable var viewModel: PortListViewModel
    @State private var protocolChoice: ProtocolChoice = .all
    @State private var icons: [String: NSImage] = [:]
    @State private var searchText = ""
    @State private var pendingKill: PortEntry?
    @State private var killMessage: String?
    @State private var isKilling = false
    @State private var showSettings = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 3

    enum ProtocolChoice: String, CaseIterable, Identifiable {
        case all = "All", tcp = "TCP", udp = "UDP"
        var id: String { rawValue }
        var filter: PortEntry.NetProtocol? {
            switch self {
            case .all: return nil
            case .tcp: return .tcp
            case .udp: return .udp
            }
        }
    }

    // System dialogs/sheets/alerts open a separate window, which a MenuBarExtra
    // panel treats as a click outside itself and dismisses — so every
    // confirmation is drawn as an overlay inside the panel's own window.
    var body: some View {
        ZStack {
            mainContent
            if showSettings {
                overlay { SettingsView(onDone: { showSettings = false }) }
            } else if let entry = pendingKill {
                overlay { killConfirmation(for: entry) }
            } else if let message = killMessage {
                overlay { killResult(message) }
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onAppear { viewModel.refreshInterval = refreshInterval }
        .onChange(of: refreshInterval) { _, value in viewModel.refreshInterval = value }
        .onChange(of: protocolChoice) { _, _ in applyCriteria() }
        .onChange(of: searchText) { _, _ in applyCriteria() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if let error = viewModel.lastError, viewModel.entries.isEmpty {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else {
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.1))
                }
                table
            }
            Divider()
            footer
        }
    }

    private func overlay<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.35)
            content()
                .padding(20)
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 12)
        }
    }

    private func killConfirmation(for entry: PortEntry) -> some View {
        VStack(spacing: 12) {
            Text("Terminate \(displayName(entry)) (PID \(String(entry.pid)))?")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Terminate (SIGTERM)", role: .destructive) { performKill(entry, signal: .terminate) }
            Button("Force Kill (SIGKILL)", role: .destructive) { performKill(entry, signal: .forceKill) }
            Button("Cancel", role: .cancel) { pendingKill = nil }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func killResult(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
            Button("OK") { killMessage = nil }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func displayName(_ entry: PortEntry) -> String {
        entry.processName ?? "pid \(String(entry.pid))"
    }

    private var filterBar: some View {
        HStack {
            Picker("Scope", selection: $viewModel.showListeningOnly) {
                Text("Listening").tag(true)
                Text("All").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            Picker("Protocol", selection: $protocolChoice) {
                ForEach(ProtocolChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            TextField("Search process, port or PID", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .padding(10)
    }

    private var table: some View {
        List {
            ForEach(viewModel.groups) { group in
                DisclosureGroup {
                    ForEach(group.entries) { entry in
                        portRow(entry)
                    }
                } label: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.inset)
    }

    private func groupHeader(_ group: ProcessGroup) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: icon(for: group))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).fontWeight(.semibold)
                Text(summary(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(group.command ?? group.path ?? "")
            Spacer()
            Text("PID \(String(group.pid))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Kill", role: .destructive) { pendingKill = group.entries.first }
                .buttonStyle(.borderless)
                .disabled(isKilling || group.entries.isEmpty)
        }
        .padding(.vertical, 2)
    }

    private func portRow(_ entry: PortEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.proto.rawValue)
                .font(.caption.monospaced())
                .frame(width: 34, alignment: .leading)
            Text(portLabel(entry))
                .frame(width: 150, alignment: .leading)
            Text(entry.remoteAddress.map { "→ \($0):\(entry.remotePort ?? "")" } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(stateLabel(entry))
                .font(.caption)
                .foregroundStyle(entry.isListening ? .green : .secondary)
                .help(stateHelp(entry))
        }
        .padding(.leading, 28)
    }

    private func summary(for group: ProcessGroup) -> String {
        var parts: [String] = []
        if group.listeningCount > 0 { parts.append("\(group.listeningCount) listening") }
        if group.connectionCount > 0 { parts.append("\(group.connectionCount) conn") }
        if let directory = group.workingDirectory, directory != "/" {
            parts.append(abbreviatingHome(directory))
        }
        return parts.joined(separator: " · ")
    }

    private func abbreviatingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func portLabel(_ entry: PortEntry) -> String {
        if let service = ServiceNames.name(for: entry) { return "\(entry.localPort) (\(service))" }
        return entry.localPort
    }

    private func stateLabel(_ entry: PortEntry) -> String {
        if entry.proto == .udp { return entry.remoteAddress == nil ? "BOUND" : "PEER" }
        return entry.state ?? ""
    }

    private func stateHelp(_ entry: PortEntry) -> String {
        if entry.proto == .udp {
            return entry.remoteAddress == nil
                ? "UDP socket bound to this port; UDP has no connection state."
                : "UDP socket talking to a specific remote peer."
        }
        switch entry.state {
        case "LISTEN": return "Waiting for incoming connections on this port."
        case "ESTABLISHED": return "Connected and exchanging data with the remote address."
        case "CLOSE_WAIT": return "Remote side closed; this process has not closed its end yet."
        case "TIME_WAIT": return "Connection closed; the port is held briefly before reuse."
        case "SYN_SENT": return "Trying to connect to the remote address."
        case "FIN_WAIT_1", "FIN_WAIT_2", "CLOSING", "LAST_ACK": return "Connection is shutting down."
        default: return entry.state ?? ""
        }
    }

    private func icon(for group: ProcessGroup) -> NSImage {
        let key = group.path ?? "pid:\(group.pid)"
        if let cached = icons[key] { return cached }
        let image: NSImage
        if let path = group.path {
            let bundle = AppBundleLocator.appBundlePath(forExecutable: path)
            image = NSWorkspace.shared.icon(forFile: bundle ?? path)
        } else {
            image = NSWorkspace.shared.icon(for: .unixExecutable)
        }
        DispatchQueue.main.async { icons[key] = image }
        return image
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.filtered.count) of \(viewModel.entries.count) connections")
            Spacer()
            if viewModel.isScanning { ProgressView().controlSize(.small) }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func applyCriteria() {
        viewModel.criteria = PortFilterCriteria(protocolFilter: protocolChoice.filter, searchText: searchText)
    }

    private func performKill(_ entry: PortEntry, signal: KillSignal) {
        pendingKill = nil
        isKilling = true
        Task {
            let result = await viewModel.kill(entry, signal: signal)
            isKilling = false
            killMessage = message(for: result, entry: entry)
        }
    }

    private func message(for result: KillResult, entry: PortEntry) -> String? {
        let name = displayName(entry)
        switch result {
        case .success:
            return nil
        case .permissionDenied:
            return "No permission to terminate \(name) (PID \(String(entry.pid))). This is usually a system process."
        case .noSuchProcess:
            return "\(name) had already exited."
        case .unknown(let errno):
            return "Could not terminate \(name): \(String(cString: strerror(errno)))"
        }
    }
}

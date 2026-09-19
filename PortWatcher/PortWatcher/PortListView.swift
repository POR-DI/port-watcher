import SwiftUI
import AppKit
import PortWatcherCore

struct PortListView: View {
    @Bindable var viewModel: PortListViewModel
    @State private var protocolChoice: ProtocolChoice = .all
    @State private var searchText = ""
    @State private var pendingKill: PortEntry?
    @State private var killMessage: String?
    @State private var isKilling = false

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

    var body: some View {
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
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: protocolChoice) { _, _ in applyCriteria() }
        .onChange(of: searchText) { _, _ in applyCriteria() }
        .confirmationDialog(
            "Terminate \(pendingKill?.processName ?? "process") (PID \(pendingKill?.pid ?? 0))?",
            isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } }),
            titleVisibility: .visible
        ) {
            Button("Terminate (SIGTERM)", role: .destructive) { performKill(.terminate) }
            Button("Force Kill (SIGKILL)", role: .destructive) { performKill(.forceKill) }
            Button("Cancel", role: .cancel) { pendingKill = nil }
        }
        .alert("Kill result", isPresented: Binding(get: { killMessage != nil }, set: { if !$0 { killMessage = nil } })) {
            Button("OK") { killMessage = nil }
        } message: {
            Text(killMessage ?? "")
        }
    }

    private var filterBar: some View {
        HStack {
            Picker("Protocol", selection: $protocolChoice) {
                ForEach(ProtocolChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            TextField("Search process, port or PID", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning)
        }
        .padding(10)
    }

    private var table: some View {
        Table(viewModel.filtered) {
            TableColumn("Process") { entry in
                HStack(spacing: 6) {
                    if let path = entry.processPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(entry.processName ?? "pid \(entry.pid)")
                }
            }
            TableColumn("PID") { entry in Text(String(entry.pid)) }.width(60)
            TableColumn("Proto") { entry in Text(entry.proto.rawValue) }.width(50)
            TableColumn("Port") { entry in Text(entry.localPort) }.width(70)
            TableColumn("Remote") { entry in
                Text(entry.remoteAddress.map { "\($0):\(entry.remotePort ?? "")" } ?? "")
            }
            TableColumn("State") { entry in Text(entry.state ?? "") }.width(100)
            TableColumn("") { entry in
                Button("Kill", role: .destructive) { pendingKill = entry }
                    .disabled(isKilling)
            }.width(50)
        }
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

    private func performKill(_ signal: KillSignal) {
        guard let entry = pendingKill else { return }
        pendingKill = nil
        isKilling = true
        Task {
            let result = await viewModel.kill(entry, signal: signal)
            isKilling = false
            killMessage = message(for: result, entry: entry)
        }
    }

    private func message(for result: KillResult, entry: PortEntry) -> String? {
        let name = entry.processName ?? "pid \(entry.pid)"
        switch result {
        case .success:
            return nil
        case .permissionDenied:
            return "No permission to terminate \(name) (PID \(entry.pid)). This is usually a system process."
        case .noSuchProcess:
            return "\(name) had already exited."
        case .unknown(let errno):
            return "Could not terminate \(name): \(String(cString: strerror(errno)))"
        }
    }
}

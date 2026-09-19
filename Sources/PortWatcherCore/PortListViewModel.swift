import Foundation
import Observation

/// Screen state for the port list. Main-actor only; scanning happens in a detached task.
@MainActor
@Observable
public final class PortListViewModel {
    public private(set) var entries: [PortEntry] = []
    public private(set) var changes: [PortChangeEvent] = []
    public var criteria = PortFilterCriteria()
    public var isScanning: Bool { inFlight != nil }
    public private(set) var lastError: String?
    public private(set) var lastKillResult: KillResult?
    public var refreshInterval: TimeInterval = 3.0
    public var onChanges: (([PortChangeEvent]) -> Void)?

    private let scanner: PortScanning
    private let resolver: ProcessInfoResolving
    private let killer: ProcessKiller
    private let monitor: PortMonitor
    private var loop: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?

    public var filtered: [PortEntry] { PortFilter.apply(criteria, to: entries) }
    public var isRunning: Bool { loop != nil }

    public init(scanner: PortScanning, resolver: ProcessInfoResolving,
                killer: ProcessKiller, monitor: PortMonitor = PortMonitor()) {
        self.scanner = scanner
        self.resolver = resolver
        self.killer = killer
        self.monitor = monitor
    }

    public convenience init() {
        self.init(scanner: PortScanner(), resolver: ProcessInfoResolver(), killer: ProcessKiller())
    }

    public func refresh() async {
        while let running = inFlight {
            await running.value
            if inFlight == running { inFlight = nil }
        }
        let task = Task { await self.performScan() }
        inFlight = task
        await task.value
        if inFlight == task { inFlight = nil }
    }

    private func performScan() async {
        let scanner = self.scanner
        let resolver = self.resolver
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try resolver.enrich(scanner.scan())
            }.value
            changes = monitor.update(with: snapshot)
            entries = monitor.entries
            lastError = nil
            onChanges?(changes)
        } catch PortScanner.ScanError.commandNotFound(let path) {
            lastError = "lsof not found at \(path)"
        } catch {
            lastError = "Scan failed: \(error)"
        }
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.refreshInterval))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func kill(_ entry: PortEntry, signal: KillSignal = .terminate) async -> KillResult {
        let result = killer.kill(pid: entry.pid, signal: signal)
        lastKillResult = result
        await refresh()
        return result
    }
}

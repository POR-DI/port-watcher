import Testing
import Darwin
import Foundation
@testable import PortWatcherCore

@MainActor
struct PortListViewModelTests {
    final class FakeScanner: PortScanning {
        var result: Result<[PortEntry], Error> = .success([])
        var scanCount = 0
        var gate: DispatchSemaphore?
        func scan() throws -> [PortEntry] {
            let snapshot = result
            gate?.wait()
            scanCount += 1
            return try snapshot.get()
        }
    }

    final class NilResolver: ProcessInfoResolving {
        func resolve(pid: Int32) -> (name: String?, path: String?) { (nil, nil) }
    }

    final class FakeKillSyscall: KillSyscalling {
        var resultToReturn: Int32 = 0
        var errnoToReturn: Int32 = 0
        var capturedPID: Int32?
        var capturedSignal: Int32?
        var lastErrno: Int32 { errnoToReturn }
        func kill(pid: Int32, signal: Int32) -> Int32 {
            capturedPID = pid
            capturedSignal = signal
            return resultToReturn
        }
    }

    func makeEntry(proto: PortEntry.NetProtocol = .tcp, port: String, pid: Int32, name: String) -> PortEntry {
        PortEntry(proto: proto, localAddress: "*", localPort: port, remoteAddress: nil,
                  remotePort: nil, state: "LISTEN", pid: pid, processName: name, processPath: nil)
    }

    func makeViewModel(scanner: FakeScanner = FakeScanner(),
                       killSyscall: FakeKillSyscall = FakeKillSyscall()) -> PortListViewModel {
        PortListViewModel(scanner: scanner, resolver: NilResolver(),
                          killer: ProcessKiller(syscall: killSyscall))
    }

    @Test func refreshPublishesScannedEntries() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(port: "3000", pid: 10, name: "node")])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        #expect(viewModel.entries.map(\.localPort) == ["3000"])
        #expect(viewModel.lastError == nil)
        #expect(viewModel.isScanning == false)
    }

    @Test func duplicateEntriesAreDeduplicated() async {
        let scanner = FakeScanner()
        let entry = makeEntry(port: "53002", pid: 654, name: "rapportd")
        scanner.result = .success([entry, entry])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        #expect(viewModel.entries.count == 1)
        #expect(viewModel.changes.count == 1)
    }

    @Test func filteredFollowsCriteria() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(proto: .tcp, port: "80", pid: 1, name: "nginx"),
                                   makeEntry(proto: .udp, port: "53", pid: 2, name: "mdns")])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        viewModel.criteria = PortFilterCriteria(protocolFilter: .udp)
        #expect(viewModel.filtered.map(\.localPort) == ["53"])
        viewModel.criteria = PortFilterCriteria(searchText: "ngin")
        #expect(viewModel.filtered.map(\.localPort) == ["80"])
    }

    @Test func scanErrorSetsLastErrorAndKeepsPreviousEntries() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(port: "80", pid: 1, name: "nginx")])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        scanner.result = .failure(PortScanner.ScanError.commandNotFound("/usr/sbin/lsof"))
        await viewModel.refresh()
        #expect(viewModel.entries.count == 1)
        #expect(viewModel.lastError == "lsof not found at /usr/sbin/lsof")
        scanner.result = .success([])
        await viewModel.refresh()
        #expect(viewModel.lastError == nil)
    }

    @Test func killUsesEntryPIDAndSignalThenRefreshes() async {
        let scanner = FakeScanner()
        let killSyscall = FakeKillSyscall()
        scanner.result = .success([makeEntry(port: "3000", pid: 42, name: "node")])
        let viewModel = makeViewModel(scanner: scanner, killSyscall: killSyscall)
        await viewModel.refresh()
        scanner.result = .success([])
        let result = await viewModel.kill(viewModel.entries[0], signal: .forceKill)
        #expect(result == .success)
        #expect(killSyscall.capturedPID == 42)
        #expect(killSyscall.capturedSignal == SIGKILL)
        #expect(viewModel.lastKillResult == .success)
        #expect(viewModel.entries.isEmpty)
        #expect(scanner.scanCount == 2)
    }

    @Test func killPermissionDeniedIsReported() async {
        let killSyscall = FakeKillSyscall()
        killSyscall.resultToReturn = -1
        killSyscall.errnoToReturn = EPERM
        let viewModel = makeViewModel(killSyscall: killSyscall)
        let result = await viewModel.kill(makeEntry(port: "22", pid: 1, name: "launchd"))
        #expect(result == .permissionDenied)
        #expect(viewModel.lastKillResult == .permissionDenied)
    }

    @Test func startIsIdempotentAndStopCancels() {
        let viewModel = makeViewModel()
        #expect(viewModel.isRunning == false)
        viewModel.start()
        viewModel.start()
        #expect(viewModel.isRunning == true)
        viewModel.stop()
        #expect(viewModel.isRunning == false)
    }

    @Test func onChangesSkipsTheFirstSnapshot() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(port: "3000", pid: 10, name: "node")])
        let viewModel = makeViewModel(scanner: scanner)
        var received: [[PortChangeEvent]] = []
        viewModel.onChanges = { received.append($0) }
        await viewModel.refresh()
        #expect(received.isEmpty)
        #expect(viewModel.changes.count == 1)
    }

    @Test func onChangesReceivesEventsAfterBaselineExists() async {
        let scanner = FakeScanner()
        let first = makeEntry(port: "3000", pid: 10, name: "node")
        scanner.result = .success([first])
        let viewModel = makeViewModel(scanner: scanner)
        var received: [[PortChangeEvent]] = []
        viewModel.onChanges = { received.append($0) }
        await viewModel.refresh()
        scanner.result = .success([first, makeEntry(port: "3001", pid: 11, name: "vite")])
        await viewModel.refresh()
        #expect(received.count == 1)
        #expect(received[0].count == 1)
        scanner.result = .success([first])
        await viewModel.refresh()
        #expect(received.count == 2)
    }

    @Test func killDuringInFlightScanWaitsThenRescans() async {
        let scanner = FakeScanner()
        let killSyscall = FakeKillSyscall()
        let entry = makeEntry(port: "3000", pid: 42, name: "node")
        scanner.result = .success([entry])
        scanner.gate = DispatchSemaphore(value: 0)
        let viewModel = makeViewModel(scanner: scanner, killSyscall: killSyscall)

        let periodic = Task { await viewModel.refresh() }
        try? await Task.sleep(for: .milliseconds(100))
        let killTask = Task { await viewModel.kill(entry) }
        try? await Task.sleep(for: .milliseconds(100))

        scanner.result = .success([])
        scanner.gate?.signal()
        scanner.gate = nil
        await periodic.value
        _ = await killTask.value

        #expect(killSyscall.capturedPID == 42)
        #expect(scanner.scanCount == 2)
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isScanning == false)
    }

    @Test func listeningOnlyIsTheDefaultScope() async {
        let scanner = FakeScanner()
        let listening = makeEntry(port: "5174", pid: 1, name: "node")
        let connected = PortEntry(proto: .tcp, localAddress: "127.0.0.1", localPort: "54321",
                                   remoteAddress: "127.0.0.1", remotePort: "5174", state: "ESTABLISHED",
                                   pid: 2, processName: "curl", processPath: nil)
        scanner.result = .success([listening, connected])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        #expect(viewModel.showListeningOnly == true)
        #expect(viewModel.filtered.map(\.localPort) == ["5174"])
        viewModel.showListeningOnly = false
        #expect(viewModel.filtered.count == 2)
    }

    @Test func groupsFollowFiltered() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(port: "5174", pid: 1, name: "node"),
                                   makeEntry(port: "5175", pid: 1, name: "node"),
                                   makeEntry(proto: .udp, port: "5353", pid: 2, name: "mdns")])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        #expect(viewModel.groups.map(\.pid) == [2, 1])
        viewModel.criteria = PortFilterCriteria(searchText: "node")
        #expect(viewModel.groups.map(\.pid) == [1])
        #expect(viewModel.groups[0].entries.count == 2)
    }
}

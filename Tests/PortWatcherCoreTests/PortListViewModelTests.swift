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

    @Test func onChangesReceivesEventsAfterRefresh() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(port: "3000", pid: 10, name: "node")])
        let viewModel = makeViewModel(scanner: scanner)
        var received: [PortChangeEvent] = []
        viewModel.onChanges = { received = $0 }
        await viewModel.refresh()
        #expect(received.count == 1)
    }
}

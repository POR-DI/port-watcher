import Testing
@testable import PortWatcherCore

struct PortMonitorTests {
    func makeEntry(port: String, pid: Int32) -> PortEntry {
        PortEntry(proto: .tcp, localAddress: "*", localPort: port, remoteAddress: nil,
                  remotePort: nil, state: "LISTEN", pid: pid, processName: "test", processPath: nil)
    }

    @Test func firstUpdateReportsAllEntriesAsOpened() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "5174", pid: 481)
        let changes = monitor.update(with: [entry])
        #expect(changes.count == 1)
        guard case .opened(let opened) = changes[0] else {
            Issue.record("expected .opened")
            return
        }
        #expect(opened.key == entry.key)
    }

    @Test func unchangedEntryProducesNoEvents() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "5174", pid: 481)
        _ = monitor.update(with: [entry])
        let changes = monitor.update(with: [entry])
        #expect(changes.isEmpty)
    }

    @Test func removedEntryProducesClosedEvent() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "5174", pid: 481)
        _ = monitor.update(with: [entry])
        let changes = monitor.update(with: [])
        #expect(changes.count == 1)
        guard case .closed(let closed) = changes[0] else {
            Issue.record("expected .closed")
            return
        }
        #expect(closed.key == entry.key)
    }

    @Test func newPortOnSamePIDProducesOpenedEvent() {
        let monitor = PortMonitor()
        let first = makeEntry(port: "5174", pid: 481)
        _ = monitor.update(with: [first])
        let second = makeEntry(port: "6000", pid: 481)
        let changes = monitor.update(with: [first, second])
        #expect(changes.count == 1)
        guard case .opened(let opened) = changes[0] else {
            Issue.record("expected .opened")
            return
        }
        #expect(opened.key.localPort == "6000")
    }

    @Test func duplicateKeysInSameSnapshotAreDeduplicated() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "53002", pid: 654)
        let duplicate = makeEntry(port: "53002", pid: 654)
        let changes = monitor.update(with: [entry, duplicate])
        #expect(changes.count == 1)
    }
}

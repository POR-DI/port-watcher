import Testing
import Foundation
@testable import PortWatcherCore

struct NotificationDebouncerTests {
    final class FakeScheduler: DebounceScheduling {
        var scheduledAction: (() -> Void)?
        var scheduleCallCount = 0
        func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
            scheduleCallCount += 1
            scheduledAction = action
        }
    }

    func makeEvent(port: String, pid: Int32) -> PortChangeEvent {
        .opened(PortEntry(proto: .tcp, localAddress: "*", localPort: port, remoteAddress: nil,
                           remotePort: nil, state: "LISTEN", pid: pid, processName: "test", processPath: nil))
    }

    @Test func flushesAllEventsInOneWindowAsSingleBatch() {
        let scheduler = FakeScheduler()
        var flushedBatches: [[PortChangeEvent]] = []
        let debouncer = NotificationDebouncer(window: 1.0, scheduler: scheduler) { batch in
            flushedBatches.append(batch)
        }
        debouncer.add([makeEvent(port: "3000", pid: 1)])
        debouncer.add([makeEvent(port: "3001", pid: 2)])
        #expect(scheduler.scheduleCallCount == 1, "should only schedule once per window")
        scheduler.scheduledAction?()
        #expect(flushedBatches.count == 1)
        #expect(flushedBatches[0].count == 2)
    }

    @Test func startsNewWindowAfterFlush() {
        let scheduler = FakeScheduler()
        var flushedBatches: [[PortChangeEvent]] = []
        let debouncer = NotificationDebouncer(window: 1.0, scheduler: scheduler) { batch in
            flushedBatches.append(batch)
        }
        debouncer.add([makeEvent(port: "3000", pid: 1)])
        scheduler.scheduledAction?()
        debouncer.add([makeEvent(port: "4000", pid: 2)])
        #expect(scheduler.scheduleCallCount == 2)
        scheduler.scheduledAction?()
        #expect(flushedBatches.count == 2)
        #expect(flushedBatches[1].count == 1)
    }

    @Test func addingEmptyEventsDoesNotSchedule() {
        let scheduler = FakeScheduler()
        let debouncer = NotificationDebouncer(window: 1.0, scheduler: scheduler) { _ in }
        debouncer.add([])
        #expect(scheduler.scheduleCallCount == 0)
    }
}

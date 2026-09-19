import Testing
import Foundation
@testable import PortWatcherCore

struct PortNotificationManagerTests {
    final class FakePoster: NotificationPosting {
        var posted: [(title: String, body: String)] = []
        func post(title: String, body: String) {
            posted.append((title, body))
        }
    }

    final class FakeScheduler: DebounceScheduling {
        var scheduledAction: (() -> Void)?
        func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
            scheduledAction = action
        }
    }

    @Test func postsSingleNotificationAfterDebounceWindowFlush() {
        let poster = FakePoster()
        let scheduler = FakeScheduler()
        let manager = PortNotificationManager(poster: poster, debounceWindow: 1.0, scheduler: scheduler)
        let entry = PortEntry(proto: .tcp, localAddress: "*", localPort: "3000", remoteAddress: nil,
                               remotePort: nil, state: "LISTEN", pid: 1, processName: "node", processPath: nil)
        manager.handle([.opened(entry)])
        #expect(poster.posted.isEmpty, "should not post before the debounce window flushes")
        scheduler.scheduledAction?()
        #expect(poster.posted.count == 1)
        #expect(poster.posted[0].body.contains("3000"))
    }
}

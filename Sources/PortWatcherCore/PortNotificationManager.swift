import Foundation
import UserNotifications

public protocol NotificationPosting {
    func post(title: String, body: String)
}

public final class UserNotificationPoster: NotificationPosting {
    public init() {}
    public func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Not thread-safe: call `handle(_:)` from the queue the scheduler dispatches to (main by default).
public final class PortNotificationManager {
    private let debouncer: NotificationDebouncer

    public init(poster: NotificationPosting = UserNotificationPoster(), debounceWindow: TimeInterval = 2.0,
                scheduler: DebounceScheduling = DispatchQueueDebounceScheduler()) {
        self.debouncer = NotificationDebouncer(window: debounceWindow, scheduler: scheduler) { events in
            poster.post(title: Self.title(for: events), body: Self.body(for: events))
        }
    }

    public func handle(_ events: [PortChangeEvent]) {
        debouncer.add(events)
    }

    static func title(for events: [PortChangeEvent]) -> String {
        events.count == 1 ? "Port change detected" : "\(events.count) port changes detected"
    }

    static func body(for events: [PortChangeEvent]) -> String {
        events.map { event in
            switch event {
            case .opened(let entry):
                return "Opened \(entry.proto.rawValue) \(entry.localPort) (\(entry.processName ?? "pid \(entry.pid)"))"
            case .closed(let entry):
                return "Closed \(entry.proto.rawValue) \(entry.localPort) (\(entry.processName ?? "pid \(entry.pid)"))"
            }
        }.joined(separator: "\n")
    }
}

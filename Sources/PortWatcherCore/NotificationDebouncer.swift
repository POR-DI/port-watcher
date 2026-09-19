import Foundation

public protocol DebounceScheduling {
    func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void)
}

public struct DispatchQueueDebounceScheduler: DebounceScheduling {
    private let queue: DispatchQueue
    public init(queue: DispatchQueue = .main) { self.queue = queue }
    public func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

/// Not thread-safe: call `add(_:)` from the queue the scheduler dispatches to (main by default).
public final class NotificationDebouncer {
    private let window: TimeInterval
    private let scheduler: DebounceScheduling
    private var pending: [PortChangeEvent] = []
    private var flushScheduled = false
    private let onFlush: ([PortChangeEvent]) -> Void

    public init(window: TimeInterval = 2.0, scheduler: DebounceScheduling = DispatchQueueDebounceScheduler(),
                onFlush: @escaping ([PortChangeEvent]) -> Void) {
        self.window = window
        self.scheduler = scheduler
        self.onFlush = onFlush
    }

    public func add(_ events: [PortChangeEvent]) {
        guard !events.isEmpty else { return }
        pending.append(contentsOf: events)
        guard !flushScheduled else { return }
        flushScheduled = true
        scheduler.schedule(after: window) { [weak self] in
            guard let self else { return }
            let batch = self.pending
            self.pending = []
            self.flushScheduled = false
            self.onFlush(batch)
        }
    }
}

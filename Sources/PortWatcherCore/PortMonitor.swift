public protocol PortMonitorDelegate: AnyObject {
    func portMonitor(_ monitor: PortMonitor, didUpdate entries: [PortEntry], changes: [PortChangeEvent])
}

/// Not thread-safe: call `update(with:)` from the main queue (or one serial queue).
public final class PortMonitor {
    public private(set) var entries: [PortEntry] = []
    private var previousEntries: [PortEntry] { entries }
    public weak var delegate: PortMonitorDelegate?

    public init() {}

    @discardableResult
    public func update(with newEntries: [PortEntry]) -> [PortChangeEvent] {
        var currentKeys = Set<PortEntry.Key>()
        let current = newEntries.filter { currentKeys.insert($0.key).inserted }
        let previousKeys = Set(previousEntries.map(\.key))

        var changes: [PortChangeEvent] = []
        for entry in current where !previousKeys.contains(entry.key) {
            changes.append(.opened(entry))
        }
        for entry in previousEntries where !currentKeys.contains(entry.key) {
            changes.append(.closed(entry))
        }

        entries = current
        delegate?.portMonitor(self, didUpdate: current, changes: changes)
        return changes
    }
}

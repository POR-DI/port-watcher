public protocol PortMonitorDelegate: AnyObject {
    func portMonitor(_ monitor: PortMonitor, didUpdate entries: [PortEntry], changes: [PortChangeEvent])
}

public final class PortMonitor {
    private var previousEntries: [PortEntry.Key: PortEntry] = [:]
    public weak var delegate: PortMonitorDelegate?

    public init() {}

    @discardableResult
    public func update(with newEntries: [PortEntry]) -> [PortChangeEvent] {
        let newByKey = Dictionary(newEntries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [PortChangeEvent] = []

        for (key, entry) in newByKey where previousEntries[key] == nil {
            changes.append(.opened(entry))
        }
        for (key, entry) in previousEntries where newByKey[key] == nil {
            changes.append(.closed(entry))
        }

        previousEntries = newByKey
        delegate?.portMonitor(self, didUpdate: newEntries, changes: changes)
        return changes
    }
}

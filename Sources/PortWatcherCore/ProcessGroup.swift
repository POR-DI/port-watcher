import Foundation

public extension PortEntry {
    /// TCP sockets in LISTEN, plus UDP sockets with no remote peer (UDP has no state).
    var isListening: Bool {
        if proto == .udp { return remoteAddress == nil }
        return state == "LISTEN"
    }
}

public struct ProcessGroup: Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    public let path: String?
    public let entries: [PortEntry]

    public var id: Int32 { pid }
    public var listeningCount: Int { entries.filter(\.isListening).count }
    public var connectionCount: Int { entries.count - listeningCount }

    public static func group(_ entries: [PortEntry]) -> [ProcessGroup] {
        var order: [Int32] = []
        var byPID: [Int32: [PortEntry]] = [:]
        for entry in entries {
            if byPID[entry.pid] == nil { order.append(entry.pid) }
            byPID[entry.pid, default: []].append(entry)
        }
        let groups = order.map { pid -> ProcessGroup in
            let items = byPID[pid] ?? []
            return ProcessGroup(pid: pid,
                                name: items.first?.processName ?? "pid \(pid)",
                                path: items.first?.processPath,
                                entries: items)
        }
        return groups.sorted { a, b in
            let aListens = a.listeningCount > 0
            let bListens = b.listeningCount > 0
            if aListens != bListens { return aListens }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

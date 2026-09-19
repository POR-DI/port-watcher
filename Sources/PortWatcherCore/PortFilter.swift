public struct PortFilterCriteria {
    public var protocolFilter: PortEntry.NetProtocol?
    public var portRange: ClosedRange<Int>?
    public var searchText: String

    public init(protocolFilter: PortEntry.NetProtocol? = nil, portRange: ClosedRange<Int>? = nil, searchText: String = "") {
        self.protocolFilter = protocolFilter
        self.portRange = portRange
        self.searchText = searchText
    }
}

public enum PortFilter {
    public static func apply(_ criteria: PortFilterCriteria, to entries: [PortEntry]) -> [PortEntry] {
        entries.filter { entry in
            if let protocolFilter = criteria.protocolFilter, entry.proto != protocolFilter {
                return false
            }
            if let range = criteria.portRange {
                guard let port = Int(entry.localPort), range.contains(port) else {
                    return false
                }
            }
            if !criteria.searchText.isEmpty {
                let haystack = "\(entry.processName ?? "") \(entry.localPort) \(entry.pid)".lowercased()
                if !haystack.contains(criteria.searchText.lowercased()) {
                    return false
                }
            }
            return true
        }
    }
}

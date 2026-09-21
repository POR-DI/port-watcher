public struct PortEntry: Hashable {
    public enum NetProtocol: String, Hashable {
        case tcp = "TCP"
        case udp = "UDP"
    }

    public struct Key: Hashable {
        public let proto: NetProtocol
        public let localAddress: String
        public let localPort: String
        public let remoteAddress: String?
        public let remotePort: String?
        public let pid: Int32
    }

    public let proto: NetProtocol
    public let localAddress: String
    public let localPort: String
    public let remoteAddress: String?
    public let remotePort: String?
    public let state: String?
    public let pid: Int32
    /// Mutable so the app layer can enrich entries via ProcessInfoResolver after scanning.
    public var processName: String?
    public var processPath: String?
    public var workingDirectory: String?
    public var command: String?

    public var key: Key {
        Key(proto: proto, localAddress: localAddress, localPort: localPort,
            remoteAddress: remoteAddress, remotePort: remotePort, pid: pid)
    }

    public init(proto: NetProtocol, localAddress: String, localPort: String,
                remoteAddress: String?, remotePort: String?, state: String?,
                pid: Int32, processName: String?, processPath: String?,
                workingDirectory: String? = nil, command: String? = nil) {
        self.proto = proto
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.state = state
        self.pid = pid
        self.processName = processName
        self.processPath = processPath
        self.workingDirectory = workingDirectory
        self.command = command
    }
}

extension PortEntry: Identifiable {
    public var id: Key { key }
}

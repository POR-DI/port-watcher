import Darwin

public enum ServiceNames {
    static let wellKnown: [Int: String] = [
        22: "ssh", 53: "dns", 80: "http", 443: "https", 25: "smtp", 587: "smtp",
        143: "imap", 993: "imaps", 445: "smb", 548: "afp", 631: "ipp", 5353: "mdns",
        1900: "ssdp", 3389: "rdp", 5900: "vnc", 7000: "airplay", 62078: "iphone-sync",
        3000: "node", 3001: "node", 4000: "phoenix", 4200: "angular", 5000: "flask/airplay",
        5001: "flask", 5173: "vite", 5174: "vite", 8000: "http-dev", 8080: "http-alt",
        8081: "metro", 8443: "https-alt", 8888: "jupyter", 19000: "expo",
        5432: "postgres", 3306: "mysql", 6379: "redis", 27017: "mongodb", 1433: "mssql",
        9200: "elasticsearch", 5672: "rabbitmq", 9092: "kafka", 2181: "zookeeper",
        11434: "ollama", 2375: "docker", 2376: "docker-tls", 27036: "steam", 27037: "steam",
    ]

    /// Built-in developer table first, then /etc/services. Main-actor only:
    /// getservbyport returns a static buffer.
    public static func name(port: Int, proto: PortEntry.NetProtocol) -> String? {
        if let known = wellKnown[port] { return known }
        guard (1...65535).contains(port) else { return nil }
        let networkOrder = Int32(UInt16(port).bigEndian)
        guard let entry = getservbyport(networkOrder, proto == .tcp ? "tcp" : "udp") else { return nil }
        return String(cString: entry.pointee.s_name)
    }

    public static func name(for entry: PortEntry) -> String? {
        guard let port = Int(entry.localPort) else { return nil }
        return name(port: port, proto: entry.proto)
    }
}

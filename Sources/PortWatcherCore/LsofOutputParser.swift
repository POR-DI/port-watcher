import Foundation

public enum LsofOutputParser {
    public static func parse(_ output: String) -> [PortEntry] {
        var entries: [PortEntry] = []
        var currentPID: Int32?
        var currentCommand: String?
        var fdProtocol: PortEntry.NetProtocol?
        var fdName: String?
        var fdState: String?

        func flushFD() {
            defer { fdProtocol = nil; fdName = nil; fdState = nil }
            guard let pid = currentPID, let proto = fdProtocol, let name = fdName else { return }
            let (local, remote) = splitAddresses(name)
            entries.append(PortEntry(
                proto: proto,
                localAddress: local.address,
                localPort: local.port,
                remoteAddress: remote?.address,
                remotePort: remote?.port,
                state: fdState,
                pid: pid,
                processName: currentCommand,
                processPath: nil
            ))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flushFD()
                currentPID = Int32(value)
                currentCommand = nil
            case "c":
                currentCommand = value
            case "f":
                flushFD()
            case "P":
                fdProtocol = PortEntry.NetProtocol(rawValue: value)
            case "n":
                fdName = value
            case "T":
                if value.hasPrefix("ST=") {
                    fdState = String(value.dropFirst(3))
                }
            default:
                break
            }
        }
        flushFD()
        return entries
    }

    private struct AddressPort { let address: String; let port: String }

    private static func splitAddresses(_ name: String) -> (local: AddressPort, remote: AddressPort?) {
        if let arrowRange = name.range(of: "->") {
            let localPart = String(name[..<arrowRange.lowerBound])
            let remotePart = String(name[arrowRange.upperBound...])
            let local = splitAddressPort(localPart)
            let remote = splitAddressPort(remotePart)
            return (local, remote)
        } else {
            let local = splitAddressPort(name)
            return (local, nil)
        }
    }

    private static func splitAddressPort(_ s: String) -> AddressPort {
        if s.hasPrefix("["), let closeIdx = s.firstIndex(of: "]") {
            let address = String(s[s.index(after: s.startIndex)..<closeIdx])
            let afterBracket = s[s.index(after: closeIdx)...]
            let port = afterBracket.hasPrefix(":") ? String(afterBracket.dropFirst()) : String(afterBracket)
            return AddressPort(address: address, port: port)
        } else if let lastColon = s.lastIndex(of: ":") {
            let address = String(s[s.startIndex..<lastColon])
            let port = String(s[s.index(after: lastColon)...])
            return AddressPort(address: address, port: port)
        } else {
            return AddressPort(address: s, port: "")
        }
    }
}

import Darwin
import Foundation

public protocol ProcessInfoResolving {
    func resolve(pid: Int32) -> (name: String?, path: String?)
    func origin(pid: Int32) -> ProcessOrigin
}

public extension ProcessInfoResolving {
    func origin(pid: Int32) -> ProcessOrigin { ProcessOrigin(workingDirectory: nil, command: nil) }
}

public final class ProcessInfoResolver: ProcessInfoResolving {
    public init() {}

    public func origin(pid: Int32) -> ProcessOrigin { ProcessOriginReader.origin(pid: pid) }

    public func resolve(pid: Int32) -> (name: String?, path: String?) {
        var buffer = [Int8](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return (name: nil, path: nil)
        }
        let path = String(cString: buffer)
        let name = (path as NSString).lastPathComponent
        return (name: name, path: path)
    }
}

public extension ProcessInfoResolving {
    /// Resolves each unique PID once; never replaces an existing name with nil.
    func enrich(_ entries: [PortEntry]) -> [PortEntry] {
        var cache: [Int32: (name: String?, path: String?, origin: ProcessOrigin)] = [:]
        return entries.map { entry in
            let info: (name: String?, path: String?, origin: ProcessOrigin)
            if let cached = cache[entry.pid] {
                info = cached
            } else {
                let resolved = resolve(pid: entry.pid)
                info = (resolved.name, resolved.path, origin(pid: entry.pid))
                cache[entry.pid] = info
            }
            var enriched = entry
            if let name = info.name { enriched.processName = name }
            enriched.processPath = info.path
            enriched.workingDirectory = info.origin.workingDirectory
            enriched.command = info.origin.command
            return enriched
        }
    }
}

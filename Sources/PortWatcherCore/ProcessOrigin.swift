import Darwin
import Foundation

/// Where a process was started from: its working directory and a short form of its command line.
public struct ProcessOrigin: Equatable {
    public var workingDirectory: String?
    public var command: String?

    public init(workingDirectory: String?, command: String?) {
        self.workingDirectory = workingDirectory
        self.command = command
    }
}

public enum ProcessOriginReader {
    public static func workingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    public static func arguments(pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// "node /x/node_modules/.bin/vite --port 5175" -> "node vite --port 5175"
    public static func summarize(arguments: [String], maxLength: Int = 80) -> String? {
        guard !arguments.isEmpty else { return nil }
        let short = arguments.map { argument -> String in
            argument.contains("/") ? (argument as NSString).lastPathComponent : argument
        }.joined(separator: " ")
        if short.count <= maxLength { return short }
        return String(short.prefix(maxLength - 1)) + "…"
    }

    public static func origin(pid: Int32) -> ProcessOrigin {
        ProcessOrigin(workingDirectory: workingDirectory(pid: pid),
                      command: arguments(pid: pid).flatMap { summarize(arguments: $0) })
    }
}

import Darwin
import Foundation

public protocol ProcessInfoResolving {
    func resolve(pid: Int32) -> (name: String?, path: String?)
}

public final class ProcessInfoResolver: ProcessInfoResolving {
    public init() {}

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

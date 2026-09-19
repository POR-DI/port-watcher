import Darwin

public protocol KillSyscalling {
    func kill(pid: Int32, signal: Int32) -> Int32
    var lastErrno: Int32 { get }
}

public struct SystemKillSyscall: KillSyscalling {
    public init() {}
    public func kill(pid: Int32, signal: Int32) -> Int32 {
        Darwin.kill(pid, signal)
    }
    public var lastErrno: Int32 { errno }
}

public enum KillSignal {
    case terminate
    case forceKill

    var rawSignal: Int32 {
        switch self {
        case .terminate: return SIGTERM
        case .forceKill: return SIGKILL
        }
    }
}

public enum KillResult: Equatable {
    case success
    case permissionDenied
    case noSuchProcess
    case unknown(errno: Int32)
}

public final class ProcessKiller {
    private let syscall: KillSyscalling

    public init(syscall: KillSyscalling = SystemKillSyscall()) {
        self.syscall = syscall
    }

    public func kill(pid: Int32, signal: KillSignal) -> KillResult {
        let result = syscall.kill(pid: pid, signal: signal.rawSignal)
        guard result != 0 else { return .success }
        switch syscall.lastErrno {
        case EPERM: return .permissionDenied
        case ESRCH: return .noSuchProcess
        default: return .unknown(errno: syscall.lastErrno)
        }
    }
}

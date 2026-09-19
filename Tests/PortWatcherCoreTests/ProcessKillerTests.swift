import Testing
import Darwin
@testable import PortWatcherCore

struct ProcessKillerTests {
    final class FakeKillSyscall: KillSyscalling {
        var resultToReturn: Int32 = 0
        var errnoToReturn: Int32 = 0
        var capturedPID: Int32?
        var capturedSignal: Int32?
        var lastErrno: Int32 { errnoToReturn }
        func kill(pid: Int32, signal: Int32) -> Int32 {
            capturedPID = pid
            capturedSignal = signal
            return resultToReturn
        }
    }

    @Test func returnsSuccessWhenSyscallReturnsZero() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = 0
        let killer = ProcessKiller(syscall: fake)
        #expect(killer.kill(pid: 481, signal: .terminate) == .success)
        #expect(fake.capturedPID == 481)
        #expect(fake.capturedSignal == SIGTERM)
    }

    @Test func returnsPermissionDeniedOnEPERM() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = -1
        fake.errnoToReturn = EPERM
        let killer = ProcessKiller(syscall: fake)
        #expect(killer.kill(pid: 1, signal: .forceKill) == .permissionDenied)
        #expect(fake.capturedSignal == SIGKILL)
    }

    @Test func returnsNoSuchProcessOnESRCH() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = -1
        fake.errnoToReturn = ESRCH
        let killer = ProcessKiller(syscall: fake)
        #expect(killer.kill(pid: 999_999, signal: .terminate) == .noSuchProcess)
    }

    @Test func returnsUnknownForOtherErrno() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = -1
        fake.errnoToReturn = EINVAL
        let killer = ProcessKiller(syscall: fake)
        #expect(killer.kill(pid: 1, signal: .terminate) == .unknown(errno: EINVAL))
    }
}

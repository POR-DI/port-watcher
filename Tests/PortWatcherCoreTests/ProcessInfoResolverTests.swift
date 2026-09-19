import Testing
import Foundation
@testable import PortWatcherCore

struct ProcessInfoResolverTests {
    @Test func resolvesNameAndPathForCurrentProcess() {
        let resolver = ProcessInfoResolver()
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let result = resolver.resolve(pid: currentPID)
        #expect(result.path != nil)
        #expect(result.name != nil)
        #expect(result.path?.contains("/") ?? false)
    }

    @Test func returnsNilForNonexistentPID() {
        let resolver = ProcessInfoResolver()
        let result = resolver.resolve(pid: 999_999)
        #expect(result.path == nil)
        #expect(result.name == nil)
    }
}

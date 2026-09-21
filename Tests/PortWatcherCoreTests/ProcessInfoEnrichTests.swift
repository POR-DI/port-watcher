import Testing
@testable import PortWatcherCore

struct ProcessInfoEnrichTests {
    final class FakeResolver: ProcessInfoResolving {
        var results: [Int32: (name: String?, path: String?)] = [:]
        var calls: [Int32] = []
        func resolve(pid: Int32) -> (name: String?, path: String?) {
            calls.append(pid)
            return results[pid] ?? (nil, nil)
        }
    }

    func makeEntry(port: String, pid: Int32, name: String?) -> PortEntry {
        PortEntry(proto: .tcp, localAddress: "*", localPort: port, remoteAddress: nil,
                  remotePort: nil, state: "LISTEN", pid: pid, processName: name, processPath: nil)
    }

    @Test func resolvesEachUniquePIDOnce() {
        let resolver = FakeResolver()
        let entries = [makeEntry(port: "80", pid: 1, name: "a"),
                       makeEntry(port: "81", pid: 1, name: "a"),
                       makeEntry(port: "82", pid: 2, name: "b")]
        _ = resolver.enrich(entries)
        #expect(resolver.calls == [1, 2])
    }

    @Test func setsPathAndUpgradesNameWhenResolved() {
        let resolver = FakeResolver()
        resolver.results[1] = (name: "com.docker.backend", path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend")
        let enriched = resolver.enrich([makeEntry(port: "80", pid: 1, name: "com.docker.bac")])
        #expect(enriched[0].processName == "com.docker.backend")
        #expect(enriched[0].processPath == "/Applications/Docker.app/Contents/MacOS/com.docker.backend")
    }

    @Test func keepsLsofNameWhenResolverReturnsNil() {
        let resolver = FakeResolver()
        let enriched = resolver.enrich([makeEntry(port: "80", pid: 1, name: "node")])
        #expect(enriched[0].processName == "node")
        #expect(enriched[0].processPath == nil)
    }

    @Test func preservesOrderAndCount() {
        let resolver = FakeResolver()
        let entries = [makeEntry(port: "3", pid: 3, name: "c"),
                       makeEntry(port: "1", pid: 1, name: "a"),
                       makeEntry(port: "2", pid: 2, name: "b")]
        let enriched = resolver.enrich(entries)
        #expect(enriched.map(\.localPort) == ["3", "1", "2"])
    }

    final class OriginResolver: ProcessInfoResolving {
        var originCalls: [Int32] = []
        func resolve(pid: Int32) -> (name: String?, path: String?) { (nil, nil) }
        func origin(pid: Int32) -> ProcessOrigin {
            originCalls.append(pid)
            return ProcessOrigin(workingDirectory: "/Users/x/proj\(pid)", command: "node vite")
        }
    }

    @Test func enrichCarriesWorkingDirectoryAndCommandOncePerPID() {
        let resolver = OriginResolver()
        let entries = [makeEntry(port: "1", pid: 1, name: "node"),
                       makeEntry(port: "2", pid: 1, name: "node"),
                       makeEntry(port: "3", pid: 2, name: "node")]
        let enriched = resolver.enrich(entries)
        #expect(enriched.map(\.workingDirectory) == ["/Users/x/proj1", "/Users/x/proj1", "/Users/x/proj2"])
        #expect(enriched.map(\.command) == ["node vite", "node vite", "node vite"])
        #expect(resolver.originCalls == [1, 2])
    }

    @Test func defaultOriginIsEmptyForResolversThatDoNotProvideIt() {
        let resolver = FakeResolver()
        let enriched = resolver.enrich([makeEntry(port: "1", pid: 1, name: "node")])
        #expect(enriched[0].workingDirectory == nil)
        #expect(enriched[0].command == nil)
    }
}

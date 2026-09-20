import Testing
@testable import PortWatcherCore

struct ServiceNamesTests {
    @Test func knowsDeveloperPortsFromBuiltInTable() {
        #expect(ServiceNames.name(port: 5174, proto: .tcp) == "vite")
        #expect(ServiceNames.name(port: 5432, proto: .tcp) == "postgres")
        #expect(ServiceNames.name(port: 27036, proto: .tcp) == "steam")
    }

    @Test func fallsBackToEtcServices() {
        #expect(ServiceNames.name(port: 21, proto: .tcp) == "ftp")
    }

    @Test func returnsNilForUnknownPort() {
        #expect(ServiceNames.name(port: 61314, proto: .tcp) == nil)
    }

    @Test func returnsNilForWildcardEntry() {
        let entry = PortEntry(proto: .udp, localAddress: "*", localPort: "*", remoteAddress: nil,
                               remotePort: nil, state: nil, pid: 1, processName: "mdns", processPath: nil)
        #expect(ServiceNames.name(for: entry) == nil)
    }
}

extension ServiceNamesTests {
    @Test func unknownPortLookupsAreCheap() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for port in 49152...50151 {
                _ = ServiceNames.name(port: port, proto: .tcp)
            }
        }
        #expect(elapsed < .milliseconds(50))
    }
}

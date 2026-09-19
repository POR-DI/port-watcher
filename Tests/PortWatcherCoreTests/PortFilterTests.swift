import Testing
@testable import PortWatcherCore

struct PortFilterTests {
    func makeEntry(proto: PortEntry.NetProtocol, port: String, name: String, pid: Int32) -> PortEntry {
        PortEntry(proto: proto, localAddress: "*", localPort: port, remoteAddress: nil,
                  remotePort: nil, state: "LISTEN", pid: pid, processName: name, processPath: nil)
    }

    @Test func filtersByProtocol() {
        let tcp = makeEntry(proto: .tcp, port: "80", name: "nginx", pid: 1)
        let udp = makeEntry(proto: .udp, port: "53", name: "dns", pid: 2)
        let criteria = PortFilterCriteria(protocolFilter: .udp)
        #expect(PortFilter.apply(criteria, to: [tcp, udp]) == [udp])
    }

    @Test func filtersByPortRange() {
        let low = makeEntry(proto: .tcp, port: "80", name: "web", pid: 1)
        let high = makeEntry(proto: .tcp, port: "9000", name: "dev", pid: 2)
        let criteria = PortFilterCriteria(portRange: 1...1024)
        #expect(PortFilter.apply(criteria, to: [low, high]) == [low])
    }

    @Test func filtersBySearchTextMatchingProcessName() {
        let nginx = makeEntry(proto: .tcp, port: "80", name: "nginx", pid: 1)
        let node = makeEntry(proto: .tcp, port: "3000", name: "node", pid: 2)
        let criteria = PortFilterCriteria(searchText: "ngin")
        #expect(PortFilter.apply(criteria, to: [nginx, node]) == [nginx])
    }

    @Test func combinesMultipleCriteria() {
        let match = makeEntry(proto: .tcp, port: "3000", name: "node", pid: 1)
        let wrongProto = makeEntry(proto: .udp, port: "3000", name: "node", pid: 2)
        let wrongRange = makeEntry(proto: .tcp, port: "80", name: "node", pid: 3)
        let criteria = PortFilterCriteria(protocolFilter: .tcp, portRange: 1024...9000, searchText: "node")
        #expect(PortFilter.apply(criteria, to: [match, wrongProto, wrongRange]) == [match])
    }

    @Test func wildcardLocalPortIsExcludedFromRangeFilterSincePortIsNotNumeric() {
        let wildcard = makeEntry(proto: .udp, port: "*", name: "mdns", pid: 1)
        let criteria = PortFilterCriteria(portRange: 1...100)
        #expect(PortFilter.apply(criteria, to: [wildcard]) == [])
    }
}

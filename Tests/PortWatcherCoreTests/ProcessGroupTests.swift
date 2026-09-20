import Testing
@testable import PortWatcherCore

struct ProcessGroupTests {
    func makeEntry(proto: PortEntry.NetProtocol = .tcp, port: String, remote: String? = nil,
                   state: String?, pid: Int32, name: String?, path: String? = nil) -> PortEntry {
        PortEntry(proto: proto, localAddress: "*", localPort: port, remoteAddress: remote,
                  remotePort: remote == nil ? nil : "1", state: state, pid: pid, processName: name, processPath: path)
    }

    @Test func isListeningRules() {
        #expect(makeEntry(port: "80", state: "LISTEN", pid: 1, name: "a").isListening == true)
        #expect(makeEntry(port: "80", remote: "1.2.3.4", state: "ESTABLISHED", pid: 1, name: "a").isListening == false)
        #expect(makeEntry(proto: .udp, port: "5353", state: nil, pid: 1, name: "a").isListening == true)
        #expect(makeEntry(proto: .udp, port: "5353", remote: "1.2.3.4", state: nil, pid: 1, name: "a").isListening == false)
    }

    @Test func groupsByPIDWithCounts() {
        let entries = [
            makeEntry(port: "27036", state: "LISTEN", pid: 15125, name: "steam_osx", path: "/Applications/Steam.app/Contents/MacOS/steam_osx"),
            makeEntry(port: "57343", remote: "127.0.0.1", state: "ESTABLISHED", pid: 15125, name: "steam_osx"),
            makeEntry(port: "5174", state: "LISTEN", pid: 481, name: "node"),
        ]
        let groups = ProcessGroup.group(entries)
        #expect(groups.count == 2)
        let steam = groups.first { $0.pid == 15125 }!
        #expect(steam.name == "steam_osx")
        #expect(steam.path == "/Applications/Steam.app/Contents/MacOS/steam_osx")
        #expect(steam.listeningCount == 1)
        #expect(steam.connectionCount == 1)
        #expect(steam.entries.count == 2)
    }

    @Test func listeningProcessesComeFirstThenByName() {
        let entries = [
            makeEntry(port: "1", remote: "1.2.3.4", state: "ESTABLISHED", pid: 3, name: "zed"),
            makeEntry(port: "2", state: "LISTEN", pid: 2, name: "node"),
            makeEntry(port: "3", state: "LISTEN", pid: 1, name: "Docker"),
        ]
        #expect(ProcessGroup.group(entries).map(\.name) == ["Docker", "node", "zed"])
    }

    @Test func fallsBackToPIDName() {
        let groups = ProcessGroup.group([makeEntry(port: "1", state: "LISTEN", pid: 77, name: nil)])
        #expect(groups[0].name == "pid 77")
    }
}

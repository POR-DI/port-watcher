import Testing
@testable import PortWatcherCore

struct LsofOutputParserTests {
    @Test func parsesSingleListeningTCPPort() {
        let output = """
        p481
        cnode
        Lpordiewtrakul
        f16
        PTCP
        n*:5174
        TST=LISTEN
        TQR=0
        TQS=0
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.pid == 481)
        #expect(entry.processName == "node")
        #expect(entry.proto == .tcp)
        #expect(entry.localAddress == "*")
        #expect(entry.localPort == "5174")
        #expect(entry.remoteAddress == nil)
        #expect(entry.remotePort == nil)
        #expect(entry.state == "LISTEN")
    }

    @Test func parsesMultipleFileDescriptorsUnderSameProcess() {
        let output = """
        p654
        crapportd
        Lpordiewtrakul
        f7
        PTCP
        n*:53002
        TST=LISTEN
        TQR=0
        TQS=0
        f15
        PTCP
        n*:53002
        TST=LISTEN
        TQR=0
        TQS=0
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.pid == 654 && $0.processName == "rapportd" })
    }

    @Test func parsesMultipleProcesses() {
        let output = """
        p481
        cnode
        Lpordiewtrakul
        f16
        PTCP
        n*:5174
        TST=LISTEN
        TQR=0
        TQS=0
        p654
        crapportd
        Lpordiewtrakul
        f7
        PTCP
        n*:53002
        TST=LISTEN
        TQR=0
        TQS=0
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 2)
        #expect(Set(entries.map { $0.pid }) == [481, 654])
    }

    @Test func parsesUDPWildcardWithNoState() {
        let output = """
        p700
        cidentityservicesd
        Lpordiewtrakul
        f7
        PUDP
        n*:*
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 1)
        #expect(entries[0].proto == .udp)
        #expect(entries[0].localAddress == "*")
        #expect(entries[0].localPort == "*")
        #expect(entries[0].state == nil)
    }

    @Test func parsesEstablishedConnectionWithRemoteAddress() {
        let output = """
        p900
        ccfprefsd
        Lpordiewtrakul
        f10
        PTCP
        n127.0.0.1:54329->127.0.0.1:53743
        TST=ESTABLISHED
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.localAddress == "127.0.0.1")
        #expect(entry.localPort == "54329")
        #expect(entry.remoteAddress == "127.0.0.1")
        #expect(entry.remotePort == "53743")
        #expect(entry.state == "ESTABLISHED")
    }

    @Test func parsesIPv6AddressesInBrackets() {
        let output = """
        p901
        csomeapp
        Lpordiewtrakul
        f36
        PTCP
        n[fe80:13::1c7a:5522:6ebf:4083]:1024->[fe80:13::cc98:4e9b:4394:c4c0]:1024
        TST=ESTABLISHED
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.localAddress == "fe80:13::1c7a:5522:6ebf:4083")
        #expect(entry.localPort == "1024")
        #expect(entry.remoteAddress == "fe80:13::cc98:4e9b:4394:c4c0")
        #expect(entry.remotePort == "1024")
    }

    @Test func ignoresUnknownFieldLinesWithoutCrashing() {
        let output = """
        p481
        cnode
        Lpordiewtrakul
        Xsomeunknownfield
        f16
        PTCP
        n*:5174
        TST=LISTEN
        """
        let entries = LsofOutputParser.parse(output)
        #expect(entries.count == 1)
    }

    @Test func emptyOutputProducesNoEntries() {
        #expect(LsofOutputParser.parse("") == [])
    }
}

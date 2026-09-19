import XCTest
@testable import PortWatcherCore

final class LsofOutputParserTests: XCTestCase {
    func test_parsesSingleListeningTCPPort() {
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
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.pid, 481)
        XCTAssertEqual(entry.processName, "node")
        XCTAssertEqual(entry.proto, .tcp)
        XCTAssertEqual(entry.localAddress, "*")
        XCTAssertEqual(entry.localPort, "5174")
        XCTAssertNil(entry.remoteAddress)
        XCTAssertNil(entry.remotePort)
        XCTAssertEqual(entry.state, "LISTEN")
    }

    func test_parsesMultipleFileDescriptorsUnderSameProcess() {
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
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.pid == 654 && $0.processName == "rapportd" })
    }

    func test_parsesMultipleProcesses() {
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
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map { $0.pid }), [481, 654])
    }

    func test_parsesUDPWildcardWithNoState() {
        let output = """
        p700
        cidentityservicesd
        Lpordiewtrakul
        f7
        PUDP
        n*:*
        """
        let entries = LsofOutputParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].proto, .udp)
        XCTAssertEqual(entries[0].localAddress, "*")
        XCTAssertEqual(entries[0].localPort, "*")
        XCTAssertNil(entries[0].state)
    }

    func test_parsesEstablishedConnectionWithRemoteAddress() {
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
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.localAddress, "127.0.0.1")
        XCTAssertEqual(entry.localPort, "54329")
        XCTAssertEqual(entry.remoteAddress, "127.0.0.1")
        XCTAssertEqual(entry.remotePort, "53743")
        XCTAssertEqual(entry.state, "ESTABLISHED")
    }

    func test_parsesIPv6AddressesInBrackets() {
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
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.localAddress, "fe80:13::1c7a:5522:6ebf:4083")
        XCTAssertEqual(entry.localPort, "1024")
        XCTAssertEqual(entry.remoteAddress, "fe80:13::cc98:4e9b:4394:c4c0")
        XCTAssertEqual(entry.remotePort, "1024")
    }

    func test_ignoresUnknownFieldLinesWithoutCrashing() {
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
        XCTAssertEqual(entries.count, 1)
    }

    func test_emptyOutputProducesNoEntries() {
        XCTAssertEqual(LsofOutputParser.parse(""), [])
    }
}

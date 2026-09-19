# Port Watcher Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `PortWatcherCore`, a pure-Swift, fully unit-tested Swift Package implementing modules 1-6 from the design spec (port scanning, process resolution, change detection, process killing, filtering, and debounced notifications) — everything the menu bar UI needs, with zero AppKit/SwiftUI dependency.

**Architecture:** A standalone Swift Package (`Package.swift` at repo root) with one library target (`PortWatcherCore`) and one test target. Every module is either a pure function/struct or wraps exactly one OS boundary (a subprocess, a syscall, a notification center) behind a small protocol so the boundary can be faked in tests. `PortMonitor` is the only stateful type; everything else is stateless.

**Tech Stack:** Swift 5.9 toolchain (confirmed installed: swift-driver 1.148.6 / Swift 6.3.3), Swift Package Manager, XCTest, Foundation, Darwin (for `proc_pidpath`/`kill`), UserNotifications. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-port-watcher-design.md`

## Global Constraints

- macOS only; native Swift, no cross-platform toolkit (spec: Constraints).
- Port data comes from shelling out to `lsof -i -P -n -F` (approach A) — not native `libproc`/`sysctl` syscalls (spec: Core approach). Confirmed binary path on this machine: `/usr/sbin/lsof`.
- No third-party dependencies — Foundation/Darwin/UserNotifications only.
- Each module (numbered 1-6 below, matching the spec's module numbers 1-6) is committed separately, per explicit user instruction (spec: Commit convention).
- `PortMonitor` is the only stateful module in this plan's scope; everything else is stateless/pure (spec: Architecture).

## Scope note (decomposition)

The spec defines 9 modules across 4 layers. This plan covers **modules 1-6 only** (Data, Domain, Notification layers — everything that is pure Swift and unit-testable without launching an app). Modules 7-9 (`MenuBarController`, `PortListView`, `SettingsView`) require an Xcode app target, AppKit/SwiftUI UI code, and — per the spec's own Testing section — can only be verified manually, not by automated tests. They get their own plan once this one is done and merged, so that plan can simply add `import PortWatcherCore` and build the UI on top of a working, tested foundation. This mirrors the "Scope Check" guidance to split independently-testable subsystems into separate plans.

## File Structure

```
port-watcher/
  Package.swift
  Sources/
    PortWatcherCore/
      PortEntry.swift              # Task 1
      LsofOutputParser.swift       # Task 1
      PortScanner.swift            # Task 2
      ProcessInfoResolver.swift    # Task 3
      PortChangeEvent.swift        # Task 4
      PortMonitor.swift            # Task 4
      ProcessKiller.swift          # Task 5
      PortFilter.swift             # Task 6
      NotificationDebouncer.swift  # Task 7
      PortNotificationManager.swift# Task 7
  Tests/
    PortWatcherCoreTests/
      LsofOutputParserTests.swift
      PortScannerTests.swift
      ProcessInfoResolverTests.swift
      PortMonitorTests.swift
      ProcessKillerTests.swift
      PortFilterTests.swift
      NotificationDebouncerTests.swift
      PortNotificationManagerTests.swift
```

---

### Task 1: PortEntry + LsofOutputParser

**Files:**
- Create: `Package.swift`
- Create: `Sources/PortWatcherCore/PortEntry.swift`
- Create: `Sources/PortWatcherCore/LsofOutputParser.swift`
- Test: `Tests/PortWatcherCoreTests/LsofOutputParserTests.swift`

**Interfaces:**
- Produces: `PortEntry` (struct, `Hashable`) with fields `proto: PortEntry.NetProtocol` (`enum { tcp, udp }`), `localAddress: String`, `localPort: String`, `remoteAddress: String?`, `remotePort: String?`, `state: String?`, `pid: Int32`, `processName: String?`, `processPath: String?`, and computed `key: PortEntry.Key` (identity tuple excluding `processName`/`processPath`). Ports are `String` (not `Int`) because `lsof` reports wildcards as `*`.
- Produces: `LsofOutputParser.parse(_ output: String) -> [PortEntry]` (static function on an enum namespace).

- [ ] **Step 1: Create the package scaffold**

```bash
mkdir -p Sources/PortWatcherCore Tests/PortWatcherCoreTests
```

Write `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortWatcherCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PortWatcherCore", targets: ["PortWatcherCore"])
    ],
    targets: [
        .target(name: "PortWatcherCore"),
        .testTarget(name: "PortWatcherCoreTests", dependencies: ["PortWatcherCore"])
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/PortWatcherCoreTests/LsofOutputParserTests.swift`. These fixtures are real `lsof -i -P -n -F pcnPTL` output captured on the dev machine (process names/values are real; PID numbers in fixtures 4-6 are illustrative since the originals weren't captured as complete records):

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter LsofOutputParserTests`
Expected: Build failure — `PortEntry` and `LsofOutputParser` don't exist yet.

- [ ] **Step 4: Write the implementation**

Create `Sources/PortWatcherCore/PortEntry.swift`:

```swift
public struct PortEntry: Hashable {
    public enum NetProtocol: String, Hashable {
        case tcp = "TCP"
        case udp = "UDP"
    }

    public struct Key: Hashable {
        public let proto: NetProtocol
        public let localAddress: String
        public let localPort: String
        public let remoteAddress: String?
        public let remotePort: String?
        public let pid: Int32
    }

    public let proto: NetProtocol
    public let localAddress: String
    public let localPort: String
    public let remoteAddress: String?
    public let remotePort: String?
    public let state: String?
    public let pid: Int32
    public var processName: String?
    public var processPath: String?

    public var key: Key {
        Key(proto: proto, localAddress: localAddress, localPort: localPort,
            remoteAddress: remoteAddress, remotePort: remotePort, pid: pid)
    }

    public init(proto: NetProtocol, localAddress: String, localPort: String,
                remoteAddress: String?, remotePort: String?, state: String?,
                pid: Int32, processName: String?, processPath: String?) {
        self.proto = proto
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.state = state
        self.pid = pid
        self.processName = processName
        self.processPath = processPath
    }
}
```

Create `Sources/PortWatcherCore/LsofOutputParser.swift`:

```swift
public enum LsofOutputParser {
    public static func parse(_ output: String) -> [PortEntry] {
        var entries: [PortEntry] = []
        var currentPID: Int32?
        var currentCommand: String?
        var fdProtocol: PortEntry.NetProtocol?
        var fdName: String?
        var fdState: String?

        func flushFD() {
            defer { fdProtocol = nil; fdName = nil; fdState = nil }
            guard let pid = currentPID, let proto = fdProtocol, let name = fdName else { return }
            let (local, remote) = splitAddresses(name)
            entries.append(PortEntry(
                proto: proto,
                localAddress: local.address,
                localPort: local.port,
                remoteAddress: remote?.address,
                remotePort: remote?.port,
                state: fdState,
                pid: pid,
                processName: currentCommand,
                processPath: nil
            ))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flushFD()
                currentPID = Int32(value)
                currentCommand = nil
            case "c":
                currentCommand = value
            case "f":
                flushFD()
            case "P":
                fdProtocol = PortEntry.NetProtocol(rawValue: value)
            case "n":
                fdName = value
            case "T":
                if value.hasPrefix("ST=") {
                    fdState = String(value.dropFirst(3))
                }
            default:
                break
            }
        }
        flushFD()
        return entries
    }

    private struct AddressPort { let address: String; let port: String }

    private static func splitAddresses(_ name: String) -> (local: AddressPort, remote: AddressPort?) {
        let parts = name.components(separatedBy: "->")
        let local = splitAddressPort(parts[0])
        let remote = parts.count > 1 ? splitAddressPort(parts[1]) : nil
        return (local, remote)
    }

    private static func splitAddressPort(_ s: String) -> AddressPort {
        if s.hasPrefix("["), let closeIdx = s.firstIndex(of: "]") {
            let address = String(s[s.index(after: s.startIndex)..<closeIdx])
            let afterBracket = s[s.index(after: closeIdx)...]
            let port = afterBracket.hasPrefix(":") ? String(afterBracket.dropFirst()) : String(afterBracket)
            return AddressPort(address: address, port: port)
        } else if let lastColon = s.lastIndex(of: ":") {
            let address = String(s[s.startIndex..<lastColon])
            let port = String(s[s.index(after: lastColon)...])
            return AddressPort(address: address, port: port)
        } else {
            return AddressPort(address: s, port: "")
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LsofOutputParserTests`
Expected: All 8 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/PortWatcherCore/PortEntry.swift Sources/PortWatcherCore/LsofOutputParser.swift Tests/PortWatcherCoreTests/LsofOutputParserTests.swift
git commit -m "feat: add PortEntry model and lsof output parser"
```

---

### Task 2: PortScanner

**Files:**
- Create: `Sources/PortWatcherCore/PortScanner.swift`
- Test: `Tests/PortWatcherCoreTests/PortScannerTests.swift`

**Interfaces:**
- Consumes: `LsofOutputParser.parse(_:)` from Task 1.
- Produces: `PortScanning` protocol with `scan() throws -> [PortEntry]`; `PortScanner` (default impl); `CommandRunning` protocol with `run(executablePath:arguments:) throws -> String`; `ProcessCommandRunner` (default impl); `PortScanner.ScanError` enum.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/PortScannerTests.swift`:

```swift
import XCTest
@testable import PortWatcherCore

final class PortScannerTests: XCTestCase {
    final class FakeCommandRunner: CommandRunning {
        var capturedPath: String?
        var capturedArguments: [String]?
        var outputToReturn: String = ""
        func run(executablePath: String, arguments: [String]) throws -> String {
            capturedPath = executablePath
            capturedArguments = arguments
            return outputToReturn
        }
    }

    func test_scanParsesRunnerOutputThroughLsofOutputParser() throws {
        let fake = FakeCommandRunner()
        fake.outputToReturn = "p481\ncnode\nLpordiewtrakul\nf16\nPTCP\nn*:5174\nTST=LISTEN\n"
        let scanner = PortScanner(lsofPath: "/usr/sbin/lsof", runner: fake)
        let entries = try scanner.scan()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].pid, 481)
    }

    func test_scanPassesExpectedArgumentsToRunner() throws {
        let fake = FakeCommandRunner()
        let scanner = PortScanner(lsofPath: "/usr/sbin/lsof", runner: fake)
        _ = try scanner.scan()
        XCTAssertEqual(fake.capturedPath, "/usr/sbin/lsof")
        XCTAssertEqual(fake.capturedArguments, ["-i", "-P", "-n", "-F", "pcnPT"])
    }

    func test_scanThrowsWhenLsofBinaryMissing() {
        let scanner = PortScanner(lsofPath: "/nonexistent/lsof", runner: FakeCommandRunner())
        XCTAssertThrowsError(try scanner.scan()) { error in
            XCTAssertEqual(error as? PortScanner.ScanError, .commandNotFound("/nonexistent/lsof"))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PortScannerTests`
Expected: Build failure — `PortScanner`, `CommandRunning` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/PortScanner.swift`:

```swift
import Foundation

public protocol CommandRunning {
    func run(executablePath: String, arguments: [String]) throws -> String
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public protocol PortScanning {
    func scan() throws -> [PortEntry]
}

public final class PortScanner: PortScanning {
    public enum ScanError: Error, Equatable {
        case commandNotFound(String)
    }

    private let lsofPath: String
    private let runner: CommandRunning

    public init(lsofPath: String = "/usr/sbin/lsof", runner: CommandRunning = ProcessCommandRunner()) {
        self.lsofPath = lsofPath
        self.runner = runner
    }

    public func scan() throws -> [PortEntry] {
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else {
            throw ScanError.commandNotFound(lsofPath)
        }
        let output = try runner.run(executablePath: lsofPath, arguments: ["-i", "-P", "-n", "-F", "pcnPT"])
        return LsofOutputParser.parse(output)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PortScannerTests`
Expected: All 3 tests PASS.

- [ ] **Step 5: Manual verification (real `lsof`, not automated)**

Run: `swift run --package-path . 2>/dev/null; true` is not applicable (library target, no executable) — instead verify with a throwaway script:

```bash
swift -e '
import Foundation
let scanner = PortScanner(lsofPath: "/usr/sbin/lsof", runner: ProcessCommandRunner())
print(try scanner.scan().count)
' -I .build/debug -L .build/debug -lPortWatcherCore
```

If that invocation is awkward in practice, it's acceptable to instead add a temporary `print` in a scratch `main.swift` outside the package, run it, confirm it prints a plausible non-zero port count, then delete the scratch file — this step produces no committed artifact either way.

- [ ] **Step 6: Commit**

```bash
git add Sources/PortWatcherCore/PortScanner.swift Tests/PortWatcherCoreTests/PortScannerTests.swift
git commit -m "feat: add PortScanner wrapping lsof via injectable CommandRunning"
```

---

### Task 3: ProcessInfoResolver

**Files:**
- Create: `Sources/PortWatcherCore/ProcessInfoResolver.swift`
- Test: `Tests/PortWatcherCoreTests/ProcessInfoResolverTests.swift`

**Interfaces:**
- Produces: `ProcessInfoResolving` protocol with `resolve(pid: Int32) -> (name: String?, path: String?)`; `ProcessInfoResolver` (default impl using `proc_pidpath`).

Confirmed on this machine: `import Darwin; proc_pidpath(pid, &buffer, UInt32(buffer.count))` compiles and correctly returns the calling process's own executable path (verified via a standalone `swiftc` script before writing this plan). No mocking seam is introduced here — `proc_pidpath` is a thin syscall wrapper with no meaningful pure-logic boundary, so the test below exercises the real syscall against the test process's own PID (deterministic, no external state).

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/ProcessInfoResolverTests.swift`:

```swift
import XCTest
import Foundation
@testable import PortWatcherCore

final class ProcessInfoResolverTests: XCTestCase {
    func test_resolvesNameAndPathForCurrentProcess() {
        let resolver = ProcessInfoResolver()
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let result = resolver.resolve(pid: currentPID)
        XCTAssertNotNil(result.path)
        XCTAssertNotNil(result.name)
        XCTAssertTrue(result.path?.contains("/") ?? false)
    }

    func test_returnsNilForNonexistentPID() {
        let resolver = ProcessInfoResolver()
        let result = resolver.resolve(pid: 999_999)
        XCTAssertNil(result.path)
        XCTAssertNil(result.name)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessInfoResolverTests`
Expected: Build failure — `ProcessInfoResolver` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/ProcessInfoResolver.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessInfoResolverTests`
Expected: Both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/ProcessInfoResolver.swift Tests/PortWatcherCoreTests/ProcessInfoResolverTests.swift
git commit -m "feat: add ProcessInfoResolver using proc_pidpath"
```

---

### Task 4: PortChangeEvent + PortMonitor

**Files:**
- Create: `Sources/PortWatcherCore/PortChangeEvent.swift`
- Create: `Sources/PortWatcherCore/PortMonitor.swift`
- Test: `Tests/PortWatcherCoreTests/PortMonitorTests.swift`

**Interfaces:**
- Consumes: `PortEntry`, `PortEntry.Key` from Task 1.
- Produces: `PortChangeEvent` enum (`.opened(PortEntry)`, `.closed(PortEntry)`); `PortMonitorDelegate` protocol; `PortMonitor` with `func update(with newEntries: [PortEntry]) -> [PortChangeEvent]`.

Design note grounded in real captured data: a single process can report two file descriptors with the identical `(proto, localAddress, localPort, remoteAddress, remotePort, pid)` tuple (observed for `rapportd`, PID 654, port 53002 — two listening sockets, likely IPv4/IPv6 dual-stack). `PortMonitor` deduplicates same-key entries within one snapshot (keeps the first) rather than crashing.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/PortMonitorTests.swift`:

```swift
import XCTest
@testable import PortWatcherCore

final class PortMonitorTests: XCTestCase {
    func makeEntry(port: String, pid: Int32) -> PortEntry {
        PortEntry(proto: .tcp, localAddress: "*", localPort: port, remoteAddress: nil,
                  remotePort: nil, state: "LISTEN", pid: pid, processName: "test", processPath: nil)
    }

    func test_firstUpdateReportsAllEntriesAsOpened() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "5174", pid: 481)
        let changes = monitor.update(with: [entry])
        XCTAssertEqual(changes.count, 1)
        guard case .opened(let opened) = changes[0] else { return XCTFail("expected .opened") }
        XCTAssertEqual(opened.key, entry.key)
    }

    func test_unchangedEntryProducesNoEvents() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "5174", pid: 481)
        _ = monitor.update(with: [entry])
        let changes = monitor.update(with: [entry])
        XCTAssertTrue(changes.isEmpty)
    }

    func test_removedEntryProducesClosedEvent() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "5174", pid: 481)
        _ = monitor.update(with: [entry])
        let changes = monitor.update(with: [])
        XCTAssertEqual(changes.count, 1)
        guard case .closed(let closed) = changes[0] else { return XCTFail("expected .closed") }
        XCTAssertEqual(closed.key, entry.key)
    }

    func test_newPortOnSamePIDProducesOpenedEvent() {
        let monitor = PortMonitor()
        let first = makeEntry(port: "5174", pid: 481)
        _ = monitor.update(with: [first])
        let second = makeEntry(port: "6000", pid: 481)
        let changes = monitor.update(with: [first, second])
        XCTAssertEqual(changes.count, 1)
        guard case .opened(let opened) = changes[0] else { return XCTFail("expected .opened") }
        XCTAssertEqual(opened.key.localPort, "6000")
    }

    func test_duplicateKeysInSameSnapshotAreDeduplicated() {
        let monitor = PortMonitor()
        let entry = makeEntry(port: "53002", pid: 654)
        let duplicate = makeEntry(port: "53002", pid: 654)
        let changes = monitor.update(with: [entry, duplicate])
        XCTAssertEqual(changes.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PortMonitorTests`
Expected: Build failure — `PortMonitor`, `PortChangeEvent` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/PortChangeEvent.swift`:

```swift
public enum PortChangeEvent {
    case opened(PortEntry)
    case closed(PortEntry)
}
```

Create `Sources/PortWatcherCore/PortMonitor.swift`:

```swift
public protocol PortMonitorDelegate: AnyObject {
    func portMonitor(_ monitor: PortMonitor, didUpdate entries: [PortEntry], changes: [PortChangeEvent])
}

public final class PortMonitor {
    private var previousEntries: [PortEntry.Key: PortEntry] = [:]
    public weak var delegate: PortMonitorDelegate?

    public init() {}

    @discardableResult
    public func update(with newEntries: [PortEntry]) -> [PortChangeEvent] {
        let newByKey = Dictionary(newEntries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [PortChangeEvent] = []

        for (key, entry) in newByKey where previousEntries[key] == nil {
            changes.append(.opened(entry))
        }
        for (key, entry) in previousEntries where newByKey[key] == nil {
            changes.append(.closed(entry))
        }

        previousEntries = newByKey
        delegate?.portMonitor(self, didUpdate: newEntries, changes: changes)
        return changes
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PortMonitorTests`
Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/PortChangeEvent.swift Sources/PortWatcherCore/PortMonitor.swift Tests/PortWatcherCoreTests/PortMonitorTests.swift
git commit -m "feat: add PortMonitor with snapshot diffing"
```

---

### Task 5: ProcessKiller

**Files:**
- Create: `Sources/PortWatcherCore/ProcessKiller.swift`
- Test: `Tests/PortWatcherCoreTests/ProcessKillerTests.swift`

**Interfaces:**
- Produces: `KillSignal` enum (`.terminate`, `.forceKill`); `KillResult` enum (`.success`, `.permissionDenied`, `.noSuchProcess`, `.unknown(errno: Int32)`); `KillSyscalling` protocol; `SystemKillSyscall` (default impl); `ProcessKiller` with `func kill(pid: Int32, signal: KillSignal) -> KillResult`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/ProcessKillerTests.swift`:

```swift
import XCTest
import Darwin
@testable import PortWatcherCore

final class ProcessKillerTests: XCTestCase {
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

    func test_returnsSuccessWhenSyscallReturnsZero() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = 0
        let killer = ProcessKiller(syscall: fake)
        XCTAssertEqual(killer.kill(pid: 481, signal: .terminate), .success)
        XCTAssertEqual(fake.capturedPID, 481)
        XCTAssertEqual(fake.capturedSignal, SIGTERM)
    }

    func test_returnsPermissionDeniedOnEPERM() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = -1
        fake.errnoToReturn = EPERM
        let killer = ProcessKiller(syscall: fake)
        XCTAssertEqual(killer.kill(pid: 1, signal: .forceKill), .permissionDenied)
        XCTAssertEqual(fake.capturedSignal, SIGKILL)
    }

    func test_returnsNoSuchProcessOnESRCH() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = -1
        fake.errnoToReturn = ESRCH
        let killer = ProcessKiller(syscall: fake)
        XCTAssertEqual(killer.kill(pid: 999_999, signal: .terminate), .noSuchProcess)
    }

    func test_returnsUnknownForOtherErrno() {
        let fake = FakeKillSyscall()
        fake.resultToReturn = -1
        fake.errnoToReturn = EINVAL
        let killer = ProcessKiller(syscall: fake)
        XCTAssertEqual(killer.kill(pid: 1, signal: .terminate), .unknown(errno: EINVAL))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessKillerTests`
Expected: Build failure — `ProcessKiller`, `KillSyscalling`, `KillSignal`, `KillResult` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/ProcessKiller.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessKillerTests`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/ProcessKiller.swift Tests/PortWatcherCoreTests/ProcessKillerTests.swift
git commit -m "feat: add ProcessKiller wrapping kill() syscall"
```

---

### Task 6: PortFilter

**Files:**
- Create: `Sources/PortWatcherCore/PortFilter.swift`
- Test: `Tests/PortWatcherCoreTests/PortFilterTests.swift`

**Interfaces:**
- Consumes: `PortEntry`, `PortEntry.NetProtocol` from Task 1.
- Produces: `PortFilterCriteria` struct (`protocolFilter: PortEntry.NetProtocol?`, `portRange: ClosedRange<Int>?`, `searchText: String`); `PortFilter.apply(_:to:) -> [PortEntry]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/PortFilterTests.swift`:

```swift
import XCTest
@testable import PortWatcherCore

final class PortFilterTests: XCTestCase {
    func makeEntry(proto: PortEntry.NetProtocol, port: String, name: String, pid: Int32) -> PortEntry {
        PortEntry(proto: proto, localAddress: "*", localPort: port, remoteAddress: nil,
                  remotePort: nil, state: "LISTEN", pid: pid, processName: name, processPath: nil)
    }

    func test_filtersByProtocol() {
        let tcp = makeEntry(proto: .tcp, port: "80", name: "nginx", pid: 1)
        let udp = makeEntry(proto: .udp, port: "53", name: "dns", pid: 2)
        let criteria = PortFilterCriteria(protocolFilter: .udp)
        XCTAssertEqual(PortFilter.apply(criteria, to: [tcp, udp]), [udp])
    }

    func test_filtersByPortRange() {
        let low = makeEntry(proto: .tcp, port: "80", name: "web", pid: 1)
        let high = makeEntry(proto: .tcp, port: "9000", name: "dev", pid: 2)
        let criteria = PortFilterCriteria(portRange: 1...1024)
        XCTAssertEqual(PortFilter.apply(criteria, to: [low, high]), [low])
    }

    func test_filtersBySearchTextMatchingProcessName() {
        let nginx = makeEntry(proto: .tcp, port: "80", name: "nginx", pid: 1)
        let node = makeEntry(proto: .tcp, port: "3000", name: "node", pid: 2)
        let criteria = PortFilterCriteria(searchText: "ngin")
        XCTAssertEqual(PortFilter.apply(criteria, to: [nginx, node]), [nginx])
    }

    func test_combinesMultipleCriteria() {
        let match = makeEntry(proto: .tcp, port: "3000", name: "node", pid: 1)
        let wrongProto = makeEntry(proto: .udp, port: "3000", name: "node", pid: 2)
        let wrongRange = makeEntry(proto: .tcp, port: "80", name: "node", pid: 3)
        let criteria = PortFilterCriteria(protocolFilter: .tcp, portRange: 1024...9000, searchText: "node")
        XCTAssertEqual(PortFilter.apply(criteria, to: [match, wrongProto, wrongRange]), [match])
    }

    func test_wildcardLocalPortIsExcludedFromRangeFilterSincePortIsNotNumeric() {
        let wildcard = makeEntry(proto: .udp, port: "*", name: "mdns", pid: 1)
        let criteria = PortFilterCriteria(portRange: 1...100)
        XCTAssertEqual(PortFilter.apply(criteria, to: [wildcard]), [])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PortFilterTests`
Expected: Build failure — `PortFilter`, `PortFilterCriteria` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/PortFilter.swift`:

```swift
public struct PortFilterCriteria {
    public var protocolFilter: PortEntry.NetProtocol?
    public var portRange: ClosedRange<Int>?
    public var searchText: String

    public init(protocolFilter: PortEntry.NetProtocol? = nil, portRange: ClosedRange<Int>? = nil, searchText: String = "") {
        self.protocolFilter = protocolFilter
        self.portRange = portRange
        self.searchText = searchText
    }
}

public enum PortFilter {
    public static func apply(_ criteria: PortFilterCriteria, to entries: [PortEntry]) -> [PortEntry] {
        entries.filter { entry in
            if let protocolFilter = criteria.protocolFilter, entry.proto != protocolFilter {
                return false
            }
            if let range = criteria.portRange {
                guard let port = Int(entry.localPort), range.contains(port) else {
                    return false
                }
            }
            if !criteria.searchText.isEmpty {
                let haystack = "\(entry.processName ?? "") \(entry.localPort) \(entry.pid)".lowercased()
                if !haystack.contains(criteria.searchText.lowercased()) {
                    return false
                }
            }
            return true
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PortFilterTests`
Expected: All 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/PortFilter.swift Tests/PortWatcherCoreTests/PortFilterTests.swift
git commit -m "feat: add PortFilter for protocol/range/search filtering"
```

---

### Task 7: NotificationDebouncer + PortNotificationManager

**Files:**
- Create: `Sources/PortWatcherCore/NotificationDebouncer.swift`
- Create: `Sources/PortWatcherCore/PortNotificationManager.swift`
- Test: `Tests/PortWatcherCoreTests/NotificationDebouncerTests.swift`
- Test: `Tests/PortWatcherCoreTests/PortNotificationManagerTests.swift`

**Interfaces:**
- Consumes: `PortChangeEvent` from Task 4.
- Produces: `DebounceScheduling` protocol, `DispatchQueueDebounceScheduler` (default impl), `NotificationDebouncer`; `NotificationPosting` protocol, `UserNotificationPoster` (default impl), `PortNotificationManager` with `func handle(_ events: [PortChangeEvent])`.

- [ ] **Step 1: Write the failing tests for NotificationDebouncer**

Create `Tests/PortWatcherCoreTests/NotificationDebouncerTests.swift`:

```swift
import XCTest
@testable import PortWatcherCore

final class NotificationDebouncerTests: XCTestCase {
    final class FakeScheduler: DebounceScheduling {
        var scheduledAction: (() -> Void)?
        var scheduleCallCount = 0
        func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
            scheduleCallCount += 1
            scheduledAction = action
        }
    }

    func makeEvent(port: String, pid: Int32) -> PortChangeEvent {
        .opened(PortEntry(proto: .tcp, localAddress: "*", localPort: port, remoteAddress: nil,
                           remotePort: nil, state: "LISTEN", pid: pid, processName: "test", processPath: nil))
    }

    func test_flushesAllEventsInOneWindowAsSingleBatch() {
        let scheduler = FakeScheduler()
        var flushedBatches: [[PortChangeEvent]] = []
        let debouncer = NotificationDebouncer(window: 1.0, scheduler: scheduler) { batch in
            flushedBatches.append(batch)
        }
        debouncer.add([makeEvent(port: "3000", pid: 1)])
        debouncer.add([makeEvent(port: "3001", pid: 2)])
        XCTAssertEqual(scheduler.scheduleCallCount, 1, "should only schedule once per window")
        scheduler.scheduledAction?()
        XCTAssertEqual(flushedBatches.count, 1)
        XCTAssertEqual(flushedBatches[0].count, 2)
    }

    func test_startsNewWindowAfterFlush() {
        let scheduler = FakeScheduler()
        var flushedBatches: [[PortChangeEvent]] = []
        let debouncer = NotificationDebouncer(window: 1.0, scheduler: scheduler) { batch in
            flushedBatches.append(batch)
        }
        debouncer.add([makeEvent(port: "3000", pid: 1)])
        scheduler.scheduledAction?()
        debouncer.add([makeEvent(port: "4000", pid: 2)])
        XCTAssertEqual(scheduler.scheduleCallCount, 2)
        scheduler.scheduledAction?()
        XCTAssertEqual(flushedBatches.count, 2)
        XCTAssertEqual(flushedBatches[1].count, 1)
    }

    func test_addingEmptyEventsDoesNotSchedule() {
        let scheduler = FakeScheduler()
        let debouncer = NotificationDebouncer(window: 1.0, scheduler: scheduler) { _ in }
        debouncer.add([])
        XCTAssertEqual(scheduler.scheduleCallCount, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotificationDebouncerTests`
Expected: Build failure — `NotificationDebouncer`, `DebounceScheduling` don't exist yet.

- [ ] **Step 3: Write NotificationDebouncer implementation**

Create `Sources/PortWatcherCore/NotificationDebouncer.swift`:

```swift
import Foundation

public protocol DebounceScheduling {
    func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void)
}

public struct DispatchQueueDebounceScheduler: DebounceScheduling {
    private let queue: DispatchQueue
    public init(queue: DispatchQueue = .main) { self.queue = queue }
    public func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

public final class NotificationDebouncer {
    private let window: TimeInterval
    private let scheduler: DebounceScheduling
    private var pending: [PortChangeEvent] = []
    private var flushScheduled = false
    private let onFlush: ([PortChangeEvent]) -> Void

    public init(window: TimeInterval = 2.0, scheduler: DebounceScheduling = DispatchQueueDebounceScheduler(),
                onFlush: @escaping ([PortChangeEvent]) -> Void) {
        self.window = window
        self.scheduler = scheduler
        self.onFlush = onFlush
    }

    public func add(_ events: [PortChangeEvent]) {
        guard !events.isEmpty else { return }
        pending.append(contentsOf: events)
        guard !flushScheduled else { return }
        flushScheduled = true
        scheduler.schedule(after: window) { [weak self] in
            guard let self else { return }
            let batch = self.pending
            self.pending = []
            self.flushScheduled = false
            self.onFlush(batch)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotificationDebouncerTests`
Expected: All 3 tests PASS.

- [ ] **Step 5: Write the failing test for PortNotificationManager**

Create `Tests/PortWatcherCoreTests/PortNotificationManagerTests.swift`:

```swift
import XCTest
@testable import PortWatcherCore

final class PortNotificationManagerTests: XCTestCase {
    final class FakePoster: NotificationPosting {
        var posted: [(title: String, body: String)] = []
        func post(title: String, body: String) {
            posted.append((title, body))
        }
    }

    final class FakeScheduler: DebounceScheduling {
        var scheduledAction: (() -> Void)?
        func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
            scheduledAction = action
        }
    }

    func test_postsSingleNotificationAfterDebounceWindowFlush() {
        let poster = FakePoster()
        let scheduler = FakeScheduler()
        let manager = PortNotificationManager(poster: poster, debounceWindow: 1.0, scheduler: scheduler)
        let entry = PortEntry(proto: .tcp, localAddress: "*", localPort: "3000", remoteAddress: nil,
                               remotePort: nil, state: "LISTEN", pid: 1, processName: "node", processPath: nil)
        manager.handle([.opened(entry)])
        XCTAssertTrue(poster.posted.isEmpty, "should not post before the debounce window flushes")
        scheduler.scheduledAction?()
        XCTAssertEqual(poster.posted.count, 1)
        XCTAssertTrue(poster.posted[0].body.contains("3000"))
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `swift test --filter PortNotificationManagerTests`
Expected: Build failure — `PortNotificationManager`, `NotificationPosting` don't exist yet.

- [ ] **Step 7: Write PortNotificationManager implementation**

Create `Sources/PortWatcherCore/PortNotificationManager.swift`:

```swift
import Foundation
import UserNotifications

public protocol NotificationPosting {
    func post(title: String, body: String)
}

public final class UserNotificationPoster: NotificationPosting {
    public init() {}
    public func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

public final class PortNotificationManager {
    private let debouncer: NotificationDebouncer

    public init(poster: NotificationPosting = UserNotificationPoster(), debounceWindow: TimeInterval = 2.0,
                scheduler: DebounceScheduling = DispatchQueueDebounceScheduler()) {
        self.debouncer = NotificationDebouncer(window: debounceWindow, scheduler: scheduler) { events in
            poster.post(title: Self.title(for: events), body: Self.body(for: events))
        }
    }

    public func handle(_ events: [PortChangeEvent]) {
        debouncer.add(events)
    }

    static func title(for events: [PortChangeEvent]) -> String {
        events.count == 1 ? "Port change detected" : "\(events.count) port changes detected"
    }

    static func body(for events: [PortChangeEvent]) -> String {
        events.map { event in
            switch event {
            case .opened(let entry):
                return "Opened \(entry.proto.rawValue) \(entry.localPort) (\(entry.processName ?? "pid \(entry.pid)"))"
            case .closed(let entry):
                return "Closed \(entry.proto.rawValue) \(entry.localPort) (\(entry.processName ?? "pid \(entry.pid)"))"
            }
        }.joined(separator: "\n")
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter PortNotificationManagerTests`
Expected: The 1 test PASSes.

- [ ] **Step 9: Run the full test suite**

Run: `swift test`
Expected: All tests across all 7 tasks PASS (26 tests total).

- [ ] **Step 10: Commit**

```bash
git add Sources/PortWatcherCore/NotificationDebouncer.swift Sources/PortWatcherCore/PortNotificationManager.swift Tests/PortWatcherCoreTests/NotificationDebouncerTests.swift Tests/PortWatcherCoreTests/PortNotificationManagerTests.swift
git commit -m "feat: add debounced port change notifications"
```

---

## After this plan

`PortWatcherCore` is a complete, tested library covering spec modules 1-6. The next plan builds the menu bar app (spec modules 7-9: `MenuBarController`, `PortListView`, `SettingsView`) as either a new executable target added to this package or a separate Xcode project depending on this package locally — that decision belongs to the next brainstorming/planning pass, not this one.

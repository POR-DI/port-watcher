# Port Watcher Grouped UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the panel readable: one expandable row per process with a real app icon and "N listening · M conn", Listening-only by default, service names next to ports, and tooltips for connection states.

**Architecture:** Pure logic in the package (`ServiceNames`, `AppBundleLocator`, `PortEntry.isListening`, `ProcessGroup`, a `showListeningOnly` scope on `PortListViewModel`), all TDD with `swift test`. The app's `PortListView` swaps its `Table` for a `List` of `DisclosureGroup`s and gains a Listening | All switch. Nothing else in the app changes.

**Tech Stack:** Swift 5 mode, Swift Testing, SwiftUI (`DisclosureGroup`, `.help`), AppKit `NSWorkspace` icons, Darwin `getservbyport`. Xcode 27 installed; `swift test` and `xcodebuild` work.

**Spec:** `docs/superpowers/specs/2026-09-20-port-watcher-grouped-ux-design.md`

## Global Constraints

- Network-free gate unchanged: `grep -rE 'socket\(|bind\(|NWListener|NWConnection|URLSession' Sources PortWatcher/PortWatcher` prints nothing. `getservbyport` only reads `/etc/services`.
- View model is `@MainActor`; `getservbyport` (static buffer, not thread-safe) is only ever called from the main actor — it is used inside `PortFilter.apply` and the view, both main-actor callers.
- Tests: Swift Testing, `swift test` (currently 48 passing). App build: `xcodebuild -project PortWatcher/PortWatcher.xcodeproj -scheme PortWatcher -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E 'error:|warning:|BUILD' | head` — only the pre-existing AppIntents warning is acceptable.
- Each task is one commit; **no Co-Authored-By or attribution trailers**.
- Existing API used verbatim: `PortEntry` (`proto`, `localPort: String`, `remoteAddress`, `state`, `pid`, `processName`, `processPath`), `PortFilter.apply(_:to:)`, `PortFilterCriteria`, `PortListViewModel` (`entries`, `criteria`, `filtered`, `kill(_:signal:)`).

## File Structure

```
Sources/PortWatcherCore/
  ServiceNames.swift        # Task 1 — new
  PortFilter.swift          # Task 1 — haystack gains service name
  AppBundleLocator.swift    # Task 2 — new
  ProcessGroup.swift        # Task 3 — new (also PortEntry.isListening)
  PortListViewModel.swift   # Task 4 — showListeningOnly, groups
Tests/PortWatcherCoreTests/
  ServiceNamesTests.swift   # Task 1
  PortFilterTests.swift     # Task 1 — one added test
  AppBundleLocatorTests.swift # Task 2
  ProcessGroupTests.swift   # Task 3
  PortListViewModelTests.swift # Task 4 — two added tests
PortWatcher/PortWatcher/
  PortListView.swift        # Task 5 — grouped list
```

---

### Task 1: ServiceNames + search by service

**Files:**
- Create: `Sources/PortWatcherCore/ServiceNames.swift`
- Modify: `Sources/PortWatcherCore/PortFilter.swift:25`
- Test: `Tests/PortWatcherCoreTests/ServiceNamesTests.swift`
- Modify: `Tests/PortWatcherCoreTests/PortFilterTests.swift` (add one test)

**Interfaces:**
- Produces: `ServiceNames.name(port: Int, proto: PortEntry.NetProtocol) -> String?` and `ServiceNames.name(for entry: PortEntry) -> String?` (nil when `localPort` is not numeric or nothing is known).
- Produces: `PortFilter` search now also matches the service name.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/ServiceNamesTests.swift`:

```swift
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
```

Append inside `struct PortFilterTests` in `Tests/PortWatcherCoreTests/PortFilterTests.swift`:

```swift
    @Test func searchMatchesServiceName() {
        let vite = makeEntry(proto: .tcp, port: "5174", name: "node", pid: 1)
        let other = makeEntry(proto: .tcp, port: "9999", name: "node", pid: 2)
        let criteria = PortFilterCriteria(searchText: "vite")
        #expect(PortFilter.apply(criteria, to: [vite, other]) == [vite])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ServiceNamesTests` → build failure, `ServiceNames` missing. `swift test --filter PortFilterTests` → `searchMatchesServiceName` fails.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/ServiceNames.swift`:

```swift
import Darwin

public enum ServiceNames {
    static let wellKnown: [Int: String] = [
        22: "ssh", 53: "dns", 80: "http", 443: "https", 25: "smtp", 587: "smtp",
        143: "imap", 993: "imaps", 445: "smb", 548: "afp", 631: "ipp", 5353: "mdns",
        1900: "ssdp", 3389: "rdp", 5900: "vnc", 7000: "airplay", 62078: "iphone-sync",
        3000: "node", 3001: "node", 4000: "phoenix", 4200: "angular", 5000: "flask/airplay",
        5001: "flask", 5173: "vite", 5174: "vite", 8000: "http-dev", 8080: "http-alt",
        8081: "metro", 8443: "https-alt", 8888: "jupyter", 19000: "expo",
        5432: "postgres", 3306: "mysql", 6379: "redis", 27017: "mongodb", 1433: "mssql",
        9200: "elasticsearch", 5672: "rabbitmq", 9092: "kafka", 2181: "zookeeper",
        11434: "ollama", 2375: "docker", 2376: "docker-tls", 27036: "steam", 27037: "steam",
    ]

    /// Built-in developer table first, then /etc/services. Main-actor only:
    /// getservbyport returns a static buffer.
    public static func name(port: Int, proto: PortEntry.NetProtocol) -> String? {
        if let known = wellKnown[port] { return known }
        guard (1...65535).contains(port) else { return nil }
        let networkOrder = Int32(UInt16(port).bigEndian)
        guard let entry = getservbyport(networkOrder, proto == .tcp ? "tcp" : "udp") else { return nil }
        return String(cString: entry.pointee.s_name)
    }

    public static func name(for entry: PortEntry) -> String? {
        guard let port = Int(entry.localPort) else { return nil }
        return name(port: port, proto: entry.proto)
    }
}
```

In `Sources/PortWatcherCore/PortFilter.swift` replace
```swift
                let haystack = "\(entry.processName ?? "") \(entry.localPort) \(entry.pid)".lowercased()
```
with
```swift
                let service = ServiceNames.name(for: entry) ?? ""
                let haystack = "\(entry.processName ?? "") \(entry.localPort) \(entry.pid) \(service)".lowercased()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ServiceNamesTests` → 4 pass. `swift test --filter PortFilterTests` → 6 pass. `swift test` → 53.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/ServiceNames.swift Sources/PortWatcherCore/PortFilter.swift Tests/PortWatcherCoreTests/ServiceNamesTests.swift Tests/PortWatcherCoreTests/PortFilterTests.swift
git commit -m "feat: name well-known ports and let search match the service name"
```

---

### Task 2: AppBundleLocator

**Files:**
- Create: `Sources/PortWatcherCore/AppBundleLocator.swift`
- Test: `Tests/PortWatcherCoreTests/AppBundleLocatorTests.swift`

**Interfaces:**
- Produces: `AppBundleLocator.appBundlePath(forExecutable path: String) -> String?` — path of the innermost enclosing `.app` directory, or nil.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/AppBundleLocatorTests.swift`:

```swift
import Testing
@testable import PortWatcherCore

struct AppBundleLocatorTests {
    @Test func findsEnclosingAppBundle() {
        let path = "/Applications/Steam.app/Contents/MacOS/steam_osx"
        #expect(AppBundleLocator.appBundlePath(forExecutable: path) == "/Applications/Steam.app")
    }

    @Test func returnsInnermostBundleWhenNested() {
        let path = "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
        #expect(AppBundleLocator.appBundlePath(forExecutable: path)
                == "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app")
    }

    @Test func returnsNilOutsideAnyBundle() {
        #expect(AppBundleLocator.appBundlePath(forExecutable: "/usr/sbin/lsof") == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppBundleLocatorTests` → build failure, `AppBundleLocator` missing.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/AppBundleLocator.swift`:

```swift
public enum AppBundleLocator {
    /// lsof reports the executable inside the bundle; the icon lives on the .app.
    public static func appBundlePath(forExecutable path: String) -> String? {
        var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while let last = components.last {
            if last.hasSuffix(".app") { return components.joined(separator: "/") }
            components.removeLast()
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppBundleLocatorTests` → 3 pass. `swift test` → 56.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/AppBundleLocator.swift Tests/PortWatcherCoreTests/AppBundleLocatorTests.swift
git commit -m "feat: locate the enclosing .app bundle for a process executable"
```

---

### Task 3: PortEntry.isListening + ProcessGroup

**Files:**
- Create: `Sources/PortWatcherCore/ProcessGroup.swift`
- Test: `Tests/PortWatcherCoreTests/ProcessGroupTests.swift`

**Interfaces:**
- Produces: `PortEntry.isListening: Bool` (TCP `LISTEN`, or UDP with `remoteAddress == nil`).
- Produces: `ProcessGroup: Identifiable, Equatable` with `pid: Int32`, `name: String`, `path: String?`, `entries: [PortEntry]`, `id: Int32` (= pid), `listeningCount: Int`, `connectionCount: Int`; `static func group(_ entries: [PortEntry]) -> [ProcessGroup]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PortWatcherCoreTests/ProcessGroupTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProcessGroupTests` → build failure, `ProcessGroup`/`isListening` missing.

- [ ] **Step 3: Write the implementation**

Create `Sources/PortWatcherCore/ProcessGroup.swift`:

```swift
import Foundation

public extension PortEntry {
    /// TCP sockets in LISTEN, plus UDP sockets with no remote peer (UDP has no state).
    var isListening: Bool {
        if proto == .udp { return remoteAddress == nil }
        return state == "LISTEN"
    }
}

public struct ProcessGroup: Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    public let path: String?
    public let entries: [PortEntry]

    public var id: Int32 { pid }
    public var listeningCount: Int { entries.filter(\.isListening).count }
    public var connectionCount: Int { entries.count - listeningCount }

    public static func group(_ entries: [PortEntry]) -> [ProcessGroup] {
        var order: [Int32] = []
        var byPID: [Int32: [PortEntry]] = [:]
        for entry in entries {
            if byPID[entry.pid] == nil { order.append(entry.pid) }
            byPID[entry.pid, default: []].append(entry)
        }
        let groups = order.map { pid -> ProcessGroup in
            let items = byPID[pid] ?? []
            return ProcessGroup(pid: pid,
                                name: items.first?.processName ?? "pid \(pid)",
                                path: items.first?.processPath,
                                entries: items)
        }
        return groups.sorted { a, b in
            let aListens = a.listeningCount > 0
            let bListens = b.listeningCount > 0
            if aListens != bListens { return aListens }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProcessGroupTests` → 4 pass. `swift test` → 60.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/ProcessGroup.swift Tests/PortWatcherCoreTests/ProcessGroupTests.swift
git commit -m "feat: group port entries by process with listening/connection counts"
```

---

### Task 4: Listening scope and groups on the view model

**Files:**
- Modify: `Sources/PortWatcherCore/PortListViewModel.swift`
- Modify: `Tests/PortWatcherCoreTests/PortListViewModelTests.swift` (add two tests)

**Interfaces:**
- Produces: `PortListViewModel.showListeningOnly: Bool` (default `true`); `filtered` applies the scope before `PortFilter`; `groups: [ProcessGroup]` computed from `filtered`.

- [ ] **Step 1: Write the failing tests**

Append inside `struct PortListViewModelTests`:

```swift
    @Test func listeningOnlyIsTheDefaultScope() async {
        let scanner = FakeScanner()
        let listening = makeEntry(port: "5174", pid: 1, name: "node")
        let connected = PortEntry(proto: .tcp, localAddress: "127.0.0.1", localPort: "54321",
                                   remoteAddress: "127.0.0.1", remotePort: "5174", state: "ESTABLISHED",
                                   pid: 2, processName: "curl", processPath: nil)
        scanner.result = .success([listening, connected])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        #expect(viewModel.showListeningOnly == true)
        #expect(viewModel.filtered.map(\.localPort) == ["5174"])
        viewModel.showListeningOnly = false
        #expect(viewModel.filtered.count == 2)
    }

    @Test func groupsFollowFiltered() async {
        let scanner = FakeScanner()
        scanner.result = .success([makeEntry(port: "5174", pid: 1, name: "node"),
                                   makeEntry(port: "5175", pid: 1, name: "node"),
                                   makeEntry(proto: .udp, port: "5353", pid: 2, name: "mdns")])
        let viewModel = makeViewModel(scanner: scanner)
        await viewModel.refresh()
        #expect(viewModel.groups.map(\.pid) == [2, 1])
        viewModel.criteria = PortFilterCriteria(searchText: "node")
        #expect(viewModel.groups.map(\.pid) == [1])
        #expect(viewModel.groups[0].entries.count == 2)
    }
```
(`makeEntry` in this suite already sets `state: "LISTEN"` and no remote, so those entries are listening; the UDP one has no remote so it is listening too. Groups sort by name: "mdns" before "node".)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PortListViewModelTests` → build failure, `showListeningOnly`/`groups` missing.

- [ ] **Step 3: Write the implementation**

In `Sources/PortWatcherCore/PortListViewModel.swift` replace
```swift
    public var filtered: [PortEntry] { PortFilter.apply(criteria, to: entries) }
```
with
```swift
    public var showListeningOnly = true

    public var filtered: [PortEntry] {
        let scoped = showListeningOnly ? entries.filter(\.isListening) : entries
        return PortFilter.apply(criteria, to: scoped)
    }

    public var groups: [ProcessGroup] { ProcessGroup.group(filtered) }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PortListViewModelTests` → 12 pass. `swift test` → 62.

- [ ] **Step 5: Commit**

```bash
git add Sources/PortWatcherCore/PortListViewModel.swift Tests/PortWatcherCoreTests/PortListViewModelTests.swift
git commit -m "feat: listening-only scope and process groups on the view model"
```

---

### Task 5: Grouped panel UI

**Files:**
- Modify: `PortWatcher/PortWatcher/PortListView.swift`

**Interfaces:**
- Consumes: `PortListViewModel.groups`, `showListeningOnly`, `kill(_:signal:)`; `ProcessGroup`; `ServiceNames.name(for:)`; `AppBundleLocator.appBundlePath(forExecutable:)`; `PortEntry.isListening`.

- [ ] **Step 1: Replace the state and filter bar**

In `PortWatcher/PortWatcher/PortListView.swift`, add after `@State private var protocolChoice: ProtocolChoice = .all`:
```swift
    @State private var scope: Scope = .listening
    @State private var icons: [String: NSImage] = [:]
```
and after the `ProtocolChoice` enum add:
```swift
    enum Scope: String, CaseIterable, Identifiable {
        case listening = "Listening", all = "All"
        var id: String { rawValue }
    }
```
In `filterBar`, replace the protocol `Picker` block (from `Picker("Protocol"` through `.frame(width: 180)`) with:
```swift
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            Picker("Protocol", selection: $protocolChoice) {
                ForEach(ProtocolChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
```
On the root modifier chain, next to `.onChange(of: protocolChoice)`, add:
```swift
        .onChange(of: scope) { _, value in viewModel.showListeningOnly = (value == .listening) }
```

- [ ] **Step 2: Replace the table with grouped rows**

Replace the whole `private var table: some View { ... }` with:
```swift
    private var table: some View {
        List {
            ForEach(viewModel.groups) { group in
                DisclosureGroup {
                    ForEach(group.entries) { entry in
                        portRow(entry)
                    }
                } label: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.inset)
    }

    private func groupHeader(_ group: ProcessGroup) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: icon(for: group))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).fontWeight(.semibold)
                Text(summary(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("PID \(String(group.pid))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Kill", role: .destructive) { pendingKill = group.entries.first }
                .buttonStyle(.borderless)
                .disabled(isKilling || group.entries.isEmpty)
        }
        .padding(.vertical, 2)
    }

    private func portRow(_ entry: PortEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.proto.rawValue)
                .font(.caption.monospaced())
                .frame(width: 34, alignment: .leading)
            Text(portLabel(entry))
                .frame(width: 150, alignment: .leading)
            Text(entry.remoteAddress.map { "→ \($0):\(entry.remotePort ?? "")" } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(stateLabel(entry))
                .font(.caption)
                .foregroundStyle(entry.isListening ? .green : .secondary)
                .help(stateHelp(entry))
        }
        .padding(.leading, 28)
    }

    private func summary(for group: ProcessGroup) -> String {
        var parts: [String] = []
        if group.listeningCount > 0 { parts.append("\(group.listeningCount) listening") }
        if group.connectionCount > 0 { parts.append("\(group.connectionCount) conn") }
        return parts.joined(separator: " · ")
    }

    private func portLabel(_ entry: PortEntry) -> String {
        if let service = ServiceNames.name(for: entry) { return "\(entry.localPort) (\(service))" }
        return entry.localPort
    }

    private func stateLabel(_ entry: PortEntry) -> String {
        if entry.proto == .udp { return entry.remoteAddress == nil ? "BOUND" : "PEER" }
        return entry.state ?? ""
    }

    private func stateHelp(_ entry: PortEntry) -> String {
        if entry.proto == .udp {
            return entry.remoteAddress == nil
                ? "UDP socket bound to this port; UDP has no connection state."
                : "UDP socket talking to a specific remote peer."
        }
        switch entry.state {
        case "LISTEN": return "Waiting for incoming connections on this port."
        case "ESTABLISHED": return "Connected and exchanging data with the remote address."
        case "CLOSE_WAIT": return "Remote side closed; this process has not closed its end yet."
        case "TIME_WAIT": return "Connection closed; the port is held briefly before reuse."
        case "SYN_SENT": return "Trying to connect to the remote address."
        case "FIN_WAIT_1", "FIN_WAIT_2", "CLOSING", "LAST_ACK": return "Connection is shutting down."
        default: return entry.state ?? ""
        }
    }

    private func icon(for group: ProcessGroup) -> NSImage {
        let key = group.path ?? "pid:\(group.pid)"
        if let cached = icons[key] { return cached }
        let image: NSImage
        if let path = group.path {
            let bundle = AppBundleLocator.appBundlePath(forExecutable: path)
            image = NSWorkspace.shared.icon(forFile: bundle ?? path)
        } else {
            image = NSWorkspace.shared.icon(for: .unixExecutable)
        }
        DispatchQueue.main.async { icons[key] = image }
        return image
    }
```
`NSWorkspace.shared.icon(for: .unixExecutable)` needs `import UniformTypeIdentifiers` — add it below `import AppKit`.

- [ ] **Step 3: Build, gate, smoke**

```bash
xcodebuild -project PortWatcher/PortWatcher.xcodeproj -scheme PortWatcher -configuration Debug -derivedDataPath .build/xcode build 2>&1 | grep -E 'error:|warning:|BUILD' | head
grep -rE 'socket\(|bind\(|NWListener|NWConnection|URLSession' Sources PortWatcher/PortWatcher; echo "exit=$?"
swift test 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`, `exit=1`, 62 tests.
Smoke: `open .build/xcode/Build/Products/Debug/PortWatcher.app`, 5 s, `pgrep -fl "PortWatcher.app/Contents/MacOS/PortWatcher"` shows it, then `pkill -f "PortWatcher.app/Contents/MacOS/PortWatcher"`.

- [ ] **Step 4: Manual verification (user)**

- [ ] Default view shows ~one row per process, far fewer rows than before; Listening | All switches scope.
- [ ] Steam / Docker / Chrome rows show their real icons; Terminal-launched things show a generic icon.
- [ ] Expanding a row lists its ports; `python3 -m http.server 8123` appears as `TCP 8123 (http-alt?)` or plain `8123` under Python; Kill on the header removes the whole process.
- [ ] Search "vite" finds the node row (if a Vite dev server is running) — otherwise search "steam".
- [ ] Hovering a state shows the tooltip.

- [ ] **Step 5: Commit**

```bash
git add PortWatcher/PortWatcher/PortListView.swift
git commit -m "feat: group the panel by process with icons, service names and state tooltips"
```

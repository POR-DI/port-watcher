# Port Watcher App (Plan 2) — Design Spec

Date: 2026-09-20
Status: Approved for implementation
Builds on: `2026-09-19-port-watcher-design.md` (modules 7-9) and the
"Carried to Plan 2" section of `../plans/2026-09-19-port-watcher-core.md`.

## Purpose

Turn the tested `PortWatcherCore` library into a runnable macOS menu bar
app. MVP is the port list with a kill action; notifications and settings
follow in the same plan as later tasks.

## Constraints

- Xcode 27.0 is now installed; `swift test` works plainly and SwiftUI /
  AppKit / UserNotifications compile. `scripts/test.sh` stays for
  machines without Xcode.
- **The app never opens a socket, binds a port, listens, connects, or
  scans the network.** All port information is read-only via `lsof`
  through `PortWatcherCore`. The only side effect the app has on the
  system is `kill()`, and only after the user confirms. Merge gate:
  `grep -rE 'socket\(|bind\(|NWListener|NWConnection|URLSession' Sources PortWatcher/`
  returns nothing.
- Hardware ports (USB, HDMI, Thunderbolt — monitors, keyboards, mice) are
  a different subsystem (IOKit) that `lsof -i` never sees; this app
  neither shows nor touches them.
- App target is a separate Xcode project (`PortWatcher.xcodeproj`) in the
  repo root that depends on the local `PortWatcherCore` package. The
  `.xcodeproj` is created by the user through Xcode's New Project wizard
  (Task 1 gives the exact clicks); everything after that is code.
- Every piece of logic that can be unit-tested lives in the package and
  is developed TDD with `swift test`. The Xcode project holds only what
  must be verified by eye.
- Menu bar only: `LSUIElement = YES` (no Dock icon, no main window).
- Threading contract from Plan 1: `PortMonitor`, `NotificationDebouncer`,
  `PortNotificationManager` are called from the main queue only.
  `PortScanner.scan()` (~70 ms) runs off-main.

## Architecture

### In the package (TDD, `swift test`)

1. **`ProcessInfoResolver.enrich(_ entries: [PortEntry]) -> [PortEntry]`**
   (extension on `ProcessInfoResolving`) — resolves each unique PID once,
   sets `processPath`, and sets `processName` only when the resolver
   returns a non-nil name (never overwrites lsof's name with nil).
2. **`PortListViewModel`** — `@MainActor @Observable final class` in a
   new `Sources/PortWatcherCore/PortListViewModel.swift`. Owns:
   - `entries: [PortEntry]` (latest deduplicated snapshot from `PortMonitor`)
   - `criteria: PortFilterCriteria`; `filtered: [PortEntry]` computed via
     `PortFilter.apply`
   - `isScanning: Bool`, `lastError: String?`, `lastKillResult: KillResult?`
   - `refreshInterval: TimeInterval` (default 3.0)
   - `func refresh() async` — scan + enrich on a background task, then
     `PortMonitor.update` on main, then publish
   - `func start()` / `func stop()` — repeating `Task` loop calling
     `refresh()` every `refreshInterval`; idempotent
   - `func kill(_ entry: PortEntry, signal: KillSignal = .terminate) async
     -> KillResult` — calls `ProcessKiller`, stores result, then `refresh()`
   - `init(scanner: PortScanning, resolver: ProcessInfoResolving,
     killer: ProcessKiller, monitor: PortMonitor = PortMonitor())` with
     production defaults in a convenience `init()`.
   - Exposes `changes: [PortChangeEvent]` from the last update so the
     notification task can subscribe later without redesign.

### In the Xcode project `PortWatcher/` (manual verification)

3. **`PortWatcherApp.swift`** — `@main` SwiftUI `App` using
   `MenuBarExtra("Port Watcher", systemImage: "network")` with
   `.menuBarExtraStyle(.window)` hosting `PortListView`. `LSUIElement`
   set in the target's Info settings. Owns one `PortListViewModel`;
   calls `start()` when the popover appears and `stop()` on disappear.
4. **`PortListView.swift`** — filter bar (segmented All/TCP/UDP + search
   field bound to `criteria`), a `Table` or `List` of `filtered` rows
   (icon via `NSWorkspace.shared.icon(forFile: processPath)`, name, PID,
   proto, local port, state), a Kill button per row → confirmation
   alert → `await viewModel.kill(entry)` → result alert. Shows
   `lastError` as a full-panel message when `entries` is empty and an
   error exists; as a top banner otherwise.
5. **Later tasks (same plan, after MVP is verified by eye):**
   `SettingsView` (refresh interval, notification toggle, launch at
   login via `SMAppService`) and notification wiring
   (`UNUserNotificationCenter.requestAuthorization` at launch,
   `PortNotificationManager.handle(viewModel.changes)`).

## Data flow

```
popover appears → viewModel.start()
  loop every refreshInterval:
    Task.detached: scanner.scan() → resolver.enrich(_:)      (off main)
    await on main: monitor.update(with:) → entries/changes published
    SwiftUI: PortFilter.apply(criteria, to: entries) → rows
popover disappears → viewModel.stop()   (no scanning while hidden)

Kill tap → confirm alert → viewModel.kill(entry)
  → ProcessKiller.kill → lastKillResult → refresh() immediately
```

## Error handling

| Failure | Behaviour |
|---|---|
| `ScanError.commandNotFound` | `lastError = "lsof not found at /usr/sbin/lsof"`; panel shows the message instead of an empty table; loop keeps running so recovery is automatic |
| Any other scan error | keep previous `entries`, show banner with `lastError`, next tick retries |
| `KillResult.permissionDenied` | alert "No permission to terminate <name> (PID n). This is usually a system process." No sudo, no retry |
| `KillResult.noSuchProcess` | brief alert "Process already exited", then refresh |
| `KillResult.unknown(errno:)` | alert with `String(cString: strerror(errno))` |
| Kill tapped twice quickly | button disabled while a kill is in flight |

## Testing

**Unit (package, TDD):**
- `enrich`: 3 entries / 2 PIDs → fake resolver called twice; nil name
  preserves lsof name; path set; order preserved.
- `PortListViewModel` with fake `PortScanning` / `ProcessInfoResolving` /
  `KillSyscalling`: `refresh()` fills `entries`; `filtered` follows
  `criteria`; `kill` passes the right PID/signal and triggers a refresh;
  scanner throw sets `lastError` and keeps previous entries;
  `start()` twice creates one loop; `stop()` cancels it.

**Manual (Xcode Run, checklist in the plan):**
- Icon in menu bar, no Dock icon; popover opens/closes.
- Rows match `lsof -i -P -n` run in Terminal at the same moment.
- Filters and search narrow the table.
- `python3 -m http.server 8000` appears; Kill removes it within one tick.
- Kill on a root-owned row → permission alert, app keeps running.
- Popover closed → no `lsof` processes spawning (`ps aux | grep lsof`).

## Out of scope

- Hardware/IOKit ports (monitors, keyboards, mice).
- Sudo/elevated kills.
- App Store distribution, notarization, auto-update.
- Native `libproc` scanning (Plan 1 approach B).

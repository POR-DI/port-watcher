# Port Watcher — Design Spec

Date: 2026-09-19
Status: Approved for implementation

## Purpose

Personal macOS menu bar utility to view open network ports on the local
machine, inspect which process owns each one, kill processes, and get
notified when ports open/close. Secondary goal: a learning project for
understanding how port/process inspection works on macOS.

## Constraints

- macOS only (target machine: Mac M5, no cross-platform requirement).
- Native Swift + SwiftUI. No Electron/cross-platform UI toolkit.
- Personal tool — no App Store distribution, no code-signing/notarization
  pipeline required for v1.
- Depends on macOS system utilities being present (`lsof`) rather than
  raw syscalls — see "Core approach" below for the trade-off considered.

## Core approach: how port data is obtained

Two approaches were considered:

- **A — Shell out to `lsof -i -P -n -F`** (chosen): parse machine-readable
  output into Swift structs. Reliable, `lsof` ships with macOS, gives
  protocol/PID/state/user in one call. Small per-call process-spawn
  overhead (~10-50ms), acceptable for a polling interval measured in
  seconds.
- **B — Native `libproc`/`sysctl` syscalls**: no external process, but
  requires hand-written C interop against largely undocumented Darwin
  structures (mirroring `lsof`'s own internals). Higher learning value,
  significantly higher implementation/debugging cost.

Decision: ship v1 on **A**. B can be explored later as a standalone
learning module if desired — it is not a dependency of the rest of the
system.

## Architecture — modules

Four layers, each module has one responsibility and communicates through
plain Swift interfaces. Layers 1-2 (Data), 3-5 (Domain), and 6
(Notification) are pure Swift with no UIKit/AppKit/SwiftUI dependency,
so they are independently unit-testable without launching the app.

### Data layer
1. **`PortScanner`** — runs `lsof -i -P -n -F` via `Process`, parses
   output into `[PortEntry]` (`protocol`, `localAddr`, `localPort`,
   `remoteAddr`, `remotePort`, `pid`, `state`). Pure snapshot, no diffing,
   no UI awareness.
2. **`ProcessInfoResolver`** — given a PID, resolves process name, full
   executable path, and icon (via `proc_pidpath` / `NSWorkspace`).
   Separate from the scanner because `lsof`'s process name field is
   sometimes truncated/insufficient.

### Domain layer
3. **`PortMonitor`** — orchestrator. Owns a refresh `Timer` (interval
   configurable), holds the previous snapshot, diffs it against each new
   snapshot, and emits `PortChangeEvent` (`.opened` / `.closed`) plus the
   full current `[PortEntry]` to subscribers. This is the **only**
   stateful module in layers 1-6 — keeping the diff logic in one place
   because it's the most bug-prone part of the system.
4. **`ProcessKiller`** — wraps the `kill()` syscall behind a protocol
   (for test injection). Takes a PID + signal (SIGTERM/SIGKILL), returns
   success/failure with a mapped error reason (permission denied, no
   such process, etc). No auto-retry.
5. **`PortFilter`** — pure function: `[PortEntry]` + filter criteria
   (protocol, port range, search text) → filtered `[PortEntry]`. No
   state.

### Notification layer
6. **`PortNotificationManager`** — subscribes to `PortMonitor` events,
   debounces bursts (e.g. a dev server restart loop opening/closing the
   same port repeatedly) into a single notification, and posts via
   `UserNotifications`.

### UI layer
7. **`MenuBarController`** — owns the `NSStatusItem` and popover
   lifecycle (AppKit; SwiftUI has no native menu-bar-item API).
8. **`PortListView`** (SwiftUI) — list/table of ports with filter bar and
   a per-row kill action.
9. **`SettingsView`** (SwiftUI) — refresh interval, notification
   toggle, launch-at-login.

## Data flow

```
Timer (interval from Settings)
   -> PortScanner.scan() -> [PortEntry] (raw, no process name yet)
   -> ProcessInfoResolver.resolve(pids:) -> entries enriched with name/path
   -> PortMonitor.update(newSnapshot:)
        - diffs against oldSnapshot
        - emits [PortChangeEvent] -> PortNotificationManager
        - emits full [PortEntry] -> UI layer
             -> PortFilter.apply(criteria:) -> filtered result
             -> PortListView renders

User taps "Kill" on a row
   -> ProcessKiller.kill(pid:, signal:) -> success/failure -> UI alert on failure
```

## Error handling

| Failure point | Likely cause | Handling |
|---|---|---|
| `lsof` not invokable | PATH/permission/sandbox issue | Detect at launch, show a clear alert instead of a silent crash |
| Malformed `lsof` output | macOS version change in output format | Parser returns `Result`/throws per-line; skip unparseable lines, don't fail the whole scan |
| Process info resolution fails | Process died between scan and resolve (race) | Fall back to showing just the PID ("Unknown process") instead of erroring the row |
| Kill fails | Permission denied, PID no longer exists | Surface the actual errno-derived reason in an alert; no automatic retry (retrying a kill against the wrong PID is dangerous) |
| Notification spam | Rapid open/close cycles (e.g. dev server restart loop) | `PortNotificationManager` debounces bursts within a short time window into one notification |

## Testing

**Unit tests (modules 1-5):**
- `PortScanner`: fixture `lsof -F` outputs (TCP, UDP, IPv6, LISTEN,
  ESTABLISHED, and malformed lines) parsed correctly without crashing.
- `PortMonitor` diff logic: given snapshot A then B, verify correct
  `.opened`/`.closed` events, including same-port-different-state and
  same-PID-new-port cases. Highest-value tests in the suite.
- `PortFilter`: each filter dimension individually and combined.
- `ProcessKiller`: mocked `kill()` via injected protocol; verify errno
  mapping to user-facing reasons.
- `PortNotificationManager` debounce: burst of events collapses to one
  notification.

**Integration test (dev-only, not CI):**
- Run `PortScanner` for real and diff its result against a direct
  `lsof -i -P -n` invocation on the dev machine.

**Manual verification (not automated):**
- Menu bar UI (`MenuBarController`, SwiftUI views) — AppKit/SwiftUI
  integration is not worth automating for a personal tool.
- Real macOS notification permission prompt and display.

## Out of scope for v1

- Cross-platform support (Windows/Linux).
- Native `libproc`/`sysctl` syscall path (approach B) — possible future
  learning exercise, not a blocker for v1.
- App Store distribution / notarization.
- Persistent history/logging of port events beyond the in-memory
  notification debounce window.

## Commit convention for this project

Each module (1-9 above) is committed separately as it's completed,
per explicit user instruction — not batched into one large commit.

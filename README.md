# Port Watcher

A macOS menu bar app that shows **which process is listening on which port**, grouped by process, with one-click kill.

## Why

- `port already in use` kept showing up while running dev servers, and hunting the culprit meant typing `lsof -i :3000` and reading a wall of text.
- Six processes all named `node` look identical in `lsof`; there is no way to tell which project each one belongs to.
- I wanted to understand ports, TCP vs UDP and processes on macOS properly, by building something real.

This is a personal tool and a learning project. It is not intended for the App Store.

## What it does

- **One row per process** — real app icon, name, how many ports it is listening on and how many connections it has, and **the folder it was started from** (e.g. `~/Downloads/lab-day-05-start`). Hover the name to see the launch command (e.g. `node vite --port 5175`).
- **Expand a row** to see each port with a known service name (`5432 (postgres)`, `5174 (vite)`) and its state (LISTEN / ESTABLISHED …). Hover a state for a plain-language explanation.
- **Listening | All** — by default only ports waiting for connections are shown (usually what you want); switch to All to see outbound connections too.
- **TCP / UDP filter** and **search** by process name, port, PID or service name.
- **Kill** a process from its row, with a confirmation offering Terminate (graceful) or Force Kill.
- **Settings** — refresh interval, launch at login.
- Scans only while the panel is open; when closed the app is idle.
- The app **never opens a socket or touches the network itself** — everything is read through `lsof`. Its only side effect is the kill you confirm.

## How to use

1. Launch the app. A network icon appears in the menu bar (no Dock icon).
2. Click the icon to see the processes that have ports open.
3. Click ▸ on a row to see its ports.
4. Found the one you don't want? **Kill → Terminate (SIGTERM)**; use **Force Kill (SIGKILL)** only if it refuses to exit.
5. The gear opens settings; Quit is in the bottom-right corner.

> Esc does not close the panel — click the menu bar icon again or click anywhere else.

## Build

Requires macOS 14 or later and Xcode (tested with Xcode 27).

```sh
git clone https://github.com/POR-DI/port-watcher.git
cd port-watcher

# build the app
xcodebuild -project PortWatcher/PortWatcher.xcodeproj -scheme PortWatcher \
  -configuration Debug -derivedDataPath .build/xcode build

# run it
open .build/xcode/Build/Products/Debug/PortWatcher.app
```

Or open `PortWatcher/PortWatcher.xcodeproj` in Xcode and press Run.

Run the logic tests (70 tests):

```sh
swift test
```

## Known limitations

- **Notifications** (alert when a port opens/closes) do not work with an ad-hoc-signed build — macOS refuses them. Add your Apple ID in Xcode → Settings → Accounts and pick a Team for the project first.
- Only processes owned by the logged-in user are visible (`lsof` without root cannot see root's or other users' processes).
- A single port cannot be closed on its own — killing means killing the whole process.
- Service names come from a built-in table plus macOS's `/etc/services`; some ports get a name that does not match their actual use (e.g. 3101 shows as `hp-pxpib`).

## Project layout

```
Sources/PortWatcherCore/    all logic (Swift Package): lsof scanning, grouping, filtering, kill, view model
Tests/PortWatcherCoreTests/ tests (Swift Testing)
PortWatcher/                the SwiftUI app (MenuBarExtra) — views only, no logic
docs/superpowers/           design specs and implementation plans for each iteration
scripts/test.sh             runs the tests on a machine with only Command Line Tools (no Xcode)
```

Principle: everything that can be tested automatically lives in the package; the app only renders and handles clicks.

## Things learned along the way

- `lsof -F` produces machine-readable output that is far easier to parse than the default table.
- One process can list the same port twice (IPv4 + IPv6); entries must be deduplicated.
- A window-style `MenuBarExtra` dismisses itself the moment another window is clicked, so system confirmation dialogs and alerts cannot be used — they have to be drawn inside the panel.
- A `getservbyport` miss costs ~5 ms and is not cached; reading `/etc/services` once at startup is much cheaper.
- `await` on an already-finished `Task` does not suspend — a loop waiting on it can spin and starve the main actor.

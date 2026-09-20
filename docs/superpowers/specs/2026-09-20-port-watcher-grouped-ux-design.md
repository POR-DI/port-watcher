# Port Watcher Grouped UX (Plan 3) — Design Spec

Date: 2026-09-20
Status: Approved for implementation
Builds on: `2026-09-20-port-watcher-app-design.md` (Plan 2, merged to main).

## Problem

After using the MVP the user reported the panel is hard to read: ~120 rows
(every connection of every process, flat), generic "exec" icons because
`lsof` points at the binary inside the bundle, and bare port numbers with
no hint of what they are.

## Decisions

- **One row per process, expandable.** Header: real app icon, process
  name, summary "N listening · M conn", one Kill button (kills the whole
  process — a single port cannot be closed without killing its owner).
  Expanding shows each port: `TCP 5174 (vite)  LISTEN`.
- **Default scope = Listening only**, with a Listening | All switch.
  "Listening" = TCP `LISTEN`, or UDP with no remote peer (UDP has no
  state). Outbound connections are hidden until the user picks All.
- **Service names** for ports: a built-in table of developer-relevant
  ports first (vite, node, postgres, redis, docker, ollama, steam, …),
  then macOS's `/etc/services` via `getservbyport`, else nothing. Search
  also matches the service name.
- **App icon** from the enclosing `.app` bundle found by walking the
  executable path upward; fall back to the executable's own icon.
- **State tooltips** on hover: LISTEN, ESTABLISHED, CLOSE_WAIT, TIME_WAIT,
  and UDP each get a one-line plain-language explanation.
- Menu bar icon and app icon are unchanged (not selected).

## Constraints (carried)

- Network-free: no sockets/bind/listen/connect; `getservbyport` only
  reads `/etc/services`. Merge gate grep unchanged.
- Logic in the package with `swift test`; the app holds only SwiftUI.
- Main-actor only for the view model; `getservbyport` uses a static
  buffer and is called only from the main actor (filter/view).
- Kill semantics, confirmations (in-panel overlays), settings and the
  notification limitation are unchanged from Plan 2.

## Architecture

Package:
1. `ServiceNames.name(port:proto:)` / `name(for: PortEntry)`; `PortFilter`
   search haystack gains the service name.
2. `AppBundleLocator.appBundlePath(forExecutable:)`.
3. `PortEntry.isListening`; `ProcessGroup` (`pid`, `name`, `path`,
   `entries`, `listeningCount`, `connectionCount`, `id = pid`) with
   `ProcessGroup.group(_:)` — groups in first-seen order, then sorted:
   processes with any listening socket first, then by name
   (case-insensitive).
4. `PortListViewModel.showListeningOnly` (default `true`) applied before
   `PortFilter`; `groups` computed from `filtered`.

App:
5. `PortListView`: filter bar gets a Listening | All segmented control;
   the table becomes a `List` of `DisclosureGroup`s per `ProcessGroup`;
   per-row state `.help()` tooltips; icon cache keyed by path.

## Error handling

Unchanged. A process whose name/path could not be resolved groups under
"pid N" with the generic icon.

## Testing

Unit: service names (table hit, `/etc/services` hit, unknown → nil,
wildcard port → nil), filter matches service name, bundle path (normal,
nested `.app`, no bundle), grouping (counts, order, name fallback),
`isListening` (TCP LISTEN / ESTABLISHED / UDP with and without remote),
view model default scope and toggle, `groups` follows `filtered`.
By eye: grouped panel readable, expand/collapse, icons real for Steam /
Docker / Chrome, Kill on a header kills the process, Listening | All
switch, tooltips, search "vite" finds the node row.

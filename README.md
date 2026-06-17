<div align="center">

# 🛰 fleetmap

### A relationship-aware macOS process & connection monitor.

*See not just **what's running**, but **what's talking to what** — processes sized by RAM, colored by CPU, wired by their live TCP and unix-socket connections.*

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white">
  <img alt="swift" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="go" src="https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="status" src="https://img.shields.io/badge/status-alpha-orange">
</p>

</div>

---

Activity Monitor tells you a process eats 60% CPU. It won't tell you that process
is wired to three others over a unix socket, or which port it's quietly listening
on. **fleetmap** draws the whole picture: a live **force-graph** of your machine
where every node is a process or app, **sized by RAM**, **colored by CPU**, and
**connected by its real sockets** — plus an Activity-Monitor-style **sortable
table** when you want the numbers.

It was born debugging a runaway process that pinned a GPU: the fix was obvious the
moment you could *see* the busy node and what it was attached to.

## Two views

| | |
| --- | --- |
| 🕸 **Graph** | Force-directed map. Node size = RAM, color = CPU (green → amber → red). Edges = live TCP + unix-socket connections. Listening ports as badges, ⚠ on all-interface ports. App helper processes collapse under their parent. |
| 📋 **List** | Sortable table — Process · CPU% · RAM · Procs · Ports · Conns · Command. Expand a grouped app to its child processes. |

## What's in here

```
app/   native macOS app (SwiftUI) — MenuBarExtra, native Table, WKWebView graph.
       Collector reads libproc directly: CPU%, RSS, app-grouping, listening
       ports, and unix/TCP edge pairing — no shelling out to ps/lsof.
cli/   the original Go tool — single binary, stdlib-only, serves the same
       graph + list as a local web page (localhost). The prototype.
```

Both speak the **same snapshot JSON** (`nodes`, `edges`), so the web canvas in
`cli/` is reused inside the native app's graph tab.

## Native app (`app/`)

```sh
cd app
swift build                      # build
./scripts/bundle.sh              # assemble FleetMap.app
open FleetMap.app
```

The collector samples every process via `proc_pidinfo` / `proc_pidfdinfo`:
instantaneous CPU (mach-timebase deltas), RSS, parent-bundle grouping, listening
TCP ports with scope, and unix-socket peers paired by `soi_so` ↔ `unsi_conn_so`
— the native equivalent of lsof's device↔peer trick.

> Without elevated rights, libproc only reads your own user's processes. A
> privileged collector (for full-system coverage including root daemons) is
> planned.

## Go CLI (`cli/`)

```sh
cd cli
go build -o fleetmap .
./fleetmap                        # serves http://localhost:<port>, opens browser
./fleetmap --min-cpu 1 --min-mb 80
```

Shells `ps` + `lsof` for system-wide coverage, pairs unix sockets by kernel
address, redacts credential-shaped command-line args, and renders a live
force-graph (canvas) + sortable table in the browser. Localhost-only.

## Design notes

- **Node identity is stable across respawns** (keyed on exec-path + args), so the
  graph doesn't flicker when a process restarts.
- **Secrets are redacted** from command lines (`--token=•••`, JWTs, `sk-`/`ghp_`
  /`AKIA`, long opaque runs) before anything renders.
- **App grouping** collapses helper processes under the outermost `.app` bundle —
  one "Brave Browser" node, not 18 helpers.
- **Edges only between visible nodes**, so system IPC hubs don't hairball.

## License

[MIT](./LICENSE).

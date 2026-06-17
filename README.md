# Port Sense

> A native macOS menu bar utility that shows which apps and processes are using your network ports — with human-readable attribution. Also lists Docker containers.
>
> 一個原生 macOS 工具,顯示哪些 App / 程序正在佔用網路埠,並提供易讀的來源辨識;也能列出 Docker 容器。

Instead of a raw `lsof` dump, Port Sense tells you *what's actually running*:

```
5173  open-slide (Vite dev server)        node
5554  Android Emulator (Medium_Phone…)    qemu-system-aarch64-headless
3000  Next.js server                      node
7679  Google Drive
```

100% local — **no network calls, no telemetry.** All data comes from `lsof`, `ps`,
`docker`, and macOS's own running-app info.

<!-- Add a screenshot here: docs/screenshot.png -->

## Features

- **Ports** — every listening TCP port with its PID, bind address (🔒 localhost /
  🌐 all-interfaces), and the owning app/tool.
- **Processes** — developer processes with live **RAM + CPU**, a **Sort by RAM/CPU**
  toggle, and search.
- **Containers** — running Docker containers, grouped into sections by Compose
  project, showing host port (left) and service name (right). Detects
  not-installed / daemon-down / no-containers states.
- **Smart attribution** — resolves a generic `node`/`python`/`java` into the real
  tool or framework (Vite, Next.js, Webpack, Vitest, Flask, Django, Gradle, …),
  the running npm package (`@open-slide/core` → `open-slide`), the **Android
  emulator** (from QEMU + `-avd`), and—via `NSRunningApplication`—the real
  (English) name of any GUI app, with no per-app rules.
- **Actions** — *Open in browser* (`http://localhost:<port>`) and *Kill process*
  (graceful `SIGTERM`, then an explicit force-quit `SIGKILL` if it survives).
- **Liquid Glass UI** — translucent panel (`NSVisualEffectView`), HIG layout,
  inset rounded rows, auto-refresh every 4s.
- **Always reachable** — a Dock icon, a **global hotkey (⌥⌘P)**, and an optional
  **Launch at Login** so it's there when you need it.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ to build from source

## Install (download)

Grab `Port Sense.dmg` from the [Releases](../../releases) page, open it, and drag
**Port Sense** to Applications.

> The app is **not signed with an Apple Developer ID** (it's a free open-source
> build), so on first launch macOS Gatekeeper will say it's from an
> unidentified developer. Open it once with **right-click → Open**, or clear the
> quarantine flag:
>
> ```bash
> xattr -dr com.apple.quarantine "/Applications/Port Sense.app"
> ```

## Build from source

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonsm/XcodeGen) (a `PortSense.xcodeproj` is also
committed for convenience).

```bash
git clone https://github.com/Yacolate0519-cmd/PortSense.git
cd PortSense
open PortSense.xcodeproj      # then ⌘R in Xcode

# or from the command line:
xcodebuild -project PortSense.xcodeproj -scheme PortSense -configuration Release build

# if you edit project.yml, regenerate:
brew install xcodegen && xcodegen generate
```

## How it works

```
PortSense/
├── PortSenseApp.swift          @main + AppDelegate: status item, floating glass
│                               panel, global hotkey, launch-at-login
├── Models.swift                PortInfo, DevProcess
├── ViewModels/ScannerStore.swift   4s auto-refresh, runs scans off the main actor
├── Services/
│   ├── CommandRunner.swift     spawn a binary with a 5s timeout (no shell)
│   ├── PortScanner.swift       lsof -nP -iTCP -sTCP:LISTEN + enrichment
│   ├── ProcessScanner.swift    ps scan, name cleanup, batched PID enrichment
│   ├── DockerScanner.swift     docker ps → containers grouped by Compose project
│   ├── Attribution.swift       pure command → human-readable label
│   ├── AppResolver.swift       PID → GUI app name via NSRunningApplication
│   └── ProcessController.swift SIGTERM → wait 1.5s → SIGKILL
├── Views/                      ContentView, Ports/Processes/Docker lists, glass bg
└── Assets.xcassets             app icon
```

- **Ports** come from `lsof -nP -iTCP -sTCP:LISTEN -F`, then each PID is enriched
  with a batched `ps -ww` (full command line) + `lsof -d cwd` (working directory),
  so attribution can go beyond `lsof`'s truncated 16-char `COMMAND`.
- **Killing** sends `SIGTERM` via `kill(2)`, polls for ~1.5 s, and only escalates
  to `SIGKILL` after the user explicitly confirms a force quit.

## A note on the menu bar icon (notched Macs)

On a MacBook with a notch, the menu bar can only fit a limited number of status
icons. If your menu bar is already full of other apps' icons, macOS may not draw
Port Sense's icon at all. That's a macOS limitation, not a bug — so Port Sense
also gives you a **global hotkey (⌥⌘P)**, a **Dock icon**, and **Launch at Login**
to make sure you can always open it.

## License

[MIT](./LICENSE) — this is a native Swift rewrite of an app originally prototyped
with Glaze.

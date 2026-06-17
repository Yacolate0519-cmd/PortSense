# Port Sense

> A native macOS **menu bar** utility that shows which apps and processes are listening on your network ports — with human-readable attribution.
>
> 一個原生 macOS 選單列工具，顯示哪些 App / 程序正在佔用網路埠，並提供易讀的來源辨識。

Instead of a raw `lsof` dump, Port Sense tells you *what's actually running*:

```
5173 · open-slide (Vite dev server)
3000 · Next.js server
11434 · Local Ollama API
```

It lives in your menu bar, opens as a popover, and lets you open a port in the
browser or kill a stuck process in two clicks. **100% local — no network, no telemetry.**

This is a native **Swift / SwiftUI** rewrite of an app originally prototyped with
the Glaze SDK. It has no third-party dependencies and builds into a standalone
`.app` you can sign, notarize, and ship as a `.dmg`.

---

## Features

- **Listening ports tab** — every listening TCP port with its PID, bind address
  (🔒 localhost / 🌐 all-interfaces / a literal IP), app name, and tool.
- **Processes tab** — running developer processes with live memory + CPU usage,
  searchable.
- **Smart attribution** — resolves a generic `node` into the real tool/package by
  reading the full command line + working directory. Detects Vite, Next.js,
  Webpack, Vitest, Jest, ts-node, Electron, nodemon, PM2; Python (uvicorn, Flask,
  Django, FastAPI, Jupyter, pytest); Java (IntelliJ, Gradle, Maven, Kafka,
  Elasticsearch); Ruby, Go, Deno, Bun, Docker, Ollama; and shells (Terminal,
  iTerm, VS Code integrated terminal, tmux, SSH). For unknown Node CLIs it
  extracts the running npm package from the path (`@open-slide/core` → `open-slide`).
- **Inline actions** — *Open in browser* (`http://localhost:<port>`) and
  *Kill process*: a graceful `SIGTERM` first, escalating to a force `SIGKILL`
  only after a second, explicit confirmation.
- **Auto-refresh** — lists refresh every 4 seconds while the popover is open.
- **Menu bar only** — no Dock icon, no main window (`LSUIElement`).

## How it works

```
PortSense/
├── PortSenseApp.swift          @main — MenuBarExtra scene (.window style)
├── Models.swift                PortInfo, DevProcess value types
├── ViewModels/
│   └── ScannerStore.swift      ObservableObject, 4s auto-refresh loop
├── Services/
│   ├── CommandRunner.swift     spawns a process with a 5s timeout (no shell)
│   ├── PortScanner.swift       lsof scan + enrichment + attribution pipeline
│   ├── ProcessScanner.swift    ps scan, name cleanup, batched PID enrichment
│   ├── Attribution.swift       pure logic: command → human-readable label
│   └── ProcessController.swift SIGTERM → wait 1.5s → SIGKILL
└── Views/
    ├── ContentView.swift       header, tabs, footer, kill confirmation flow
    ├── PortsListView.swift
    └── ProcessesListView.swift
```

- **Ports** come from `lsof -nP -iTCP -sTCP:LISTEN -F`. Because `lsof` only
  reports a truncated command, each PID is then enriched with a batched
  `ps -ww` (full command line) and `lsof -d cwd` (working directory) — two
  system calls total per scan.
- **Attribution** (`Attribution.swift`) is a pure, side-effect-free function that
  maps the enriched command to a readable label.
- **Killing** sends `SIGTERM` via `kill(2)`, polls for up to 1.5 s, and only
  escalates to `SIGKILL` after the user explicitly confirms a force quit.
- All probing uses the system binaries `/usr/sbin/lsof` and `/bin/ps`, spawned
  directly (no shell) with a timeout.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (to build)

## Build & run

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonsm/XcodeGen). A pre-generated `PortSense.xcodeproj`
is committed, so the quickest path is:

```bash
git clone https://github.com/<you>/PortSense.git
cd PortSense
open PortSense.xcodeproj        # then press ⌘R in Xcode
```

If you change `project.yml` (the source of truth), regenerate the project:

```bash
brew install xcodegen
xcodegen generate
```

Or build from the command line:

```bash
xcodegen generate   # if the .xcodeproj is missing
xcodebuild -project PortSense.xcodeproj -scheme "Port Sense" -configuration Release build
```

The built **Port Sense.app** appears in `~/Library/Developer/Xcode/DerivedData/...`
(or your chosen build folder). Launch it and look for the ⚡️ icon in the menu bar.

## Distributing a `.dmg`

Because this is a standalone native app, you can ship it like any other Mac app:

1. **Archive** in Xcode (Product → Archive) or `xcodebuild archive`.
2. **Sign** with a *Developer ID Application* certificate (requires a paid Apple
   Developer account) — the project enables Hardened Runtime, which notarization
   requires.
3. **Notarize** with `notarytool` and **staple** the ticket.
4. **Package** the `.app` into a `.dmg` (e.g. with
   [`create-dmg`](https://github.com/create-dmg/create-dmg)).

Without a Developer ID, you can still share the `.app`/`.dmg`, but recipients must
right-click → *Open* (or clear the quarantine attribute) the first time.

## Permissions

Port Sense reads only your own processes' ports and metadata via `lsof`/`ps`. It
does not require the App Sandbox (it spawns those system tools) and makes **no
network connections**.

## License

[MIT](./LICENSE)

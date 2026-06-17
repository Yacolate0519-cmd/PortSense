# Port Sense

> Know exactly what's using your Mac's ports — at a glance.
>
> 一眼看懂你的 Mac 上哪個 App 正在用哪個埠。

Ever hit **"port already in use"** and had no idea which app to blame? Or wondered
what that random `localhost:5173` is? Port Sense lives in your menu bar and tells
you — in plain language — exactly what's running on every port.

```
5173  open-slide (Vite dev server)
5554  Android Emulator (Medium_Phone_API_36.1)
3000  Next.js server
7679  Google Drive
```

No more cryptic `lsof` output. Just the answer.

<!-- Screenshot: docs/screenshot.png -->

## What it does

- **See every open port** — every listening port on your Mac, with the actual
  app or tool behind it (not a vague `node` or `qemu`).
- **Spot what's hogging your Mac** — a Processes view with live memory and CPU,
  sortable by either, so you can find the resource hog fast.
- **Peek into Docker** — your running containers grouped by project, with the
  ports they expose.
- **Fix it in one click** — open a port in your browser, or kill a stuck process
  (asks before force-quitting).
- **Always one shortcut away** — open it with **⌥⌘P** from anywhere, from the
  menu bar, or from the Dock.
- **Private by design** — everything runs locally on your Mac. No network, no
  accounts, no tracking.

## Who it's for

Developers, really. If you run dev servers, databases, simulators, or Docker,
Port Sense saves you the "what's on this port / why won't this port free up"
detective work.

## Install

1. Download **Port Sense.dmg** from the [Releases](../../releases) page.
2. Open it and drag **Port Sense** into Applications.
3. Launch it and press **⌥⌘P** (or click the icon in the menu bar).

## Using it

- **⌥⌘P** — show/hide the window from anywhere.
- **Menu bar / Dock icon** — click to open.
- Hover a row to reveal **Open in browser** and **Kill** actions.
- Gear menu → **Launch at Login** to have it ready every time you start your Mac.

## Build from source

Requires macOS 13+ and Xcode 15+.

```bash
git clone https://github.com/Yacolate0519-cmd/PortSense.git
cd PortSense
open PortSense.xcodeproj   # then press ⌘R
```

Built natively in Swift / SwiftUI — no third-party dependencies.

## License

[MIT](./LICENSE)

# Omarchy Dual Monitor Wallpaper

An [Omarchy](https://omarchy.org) shell plugin that shows **two distinct
wallpapers, one per monitor**: the **left** monitor displays the image whose
file name ends in `_L`, the **right** monitor the one ending in `_R`. The
wallpaper folder, which physical monitor is left and which is right, and which
pair is currently shown are all configurable from a bar panel, and the whole
thing is controllable over IPC.

```
forest_L.png  →  left monitor
forest_R.png  →  right monitor        (one "pair")
```

---

## Files

| File            | Role                                                                 |
|-----------------|----------------------------------------------------------------------|
| `manifest.json` | Plugin metadata (id, kinds, entry points, bar-widget info).          |
| `Service.qml`   | The long-lived **service**: owns all state, renders the per-screen background windows, exposes the IPC target `dualwallpaper`. |
| `Panel.qml`     | The **bar widget**: the bar icon + the config panel. Reads state from and calls into the service. |
| `Model.js`      | **Pure logic** (no QML): file-name matching, pair grouping, screen parsing. Shared by service and panel. |
| `README.md`     | This file.                                                           |

`manifest.json` declares `kinds: ["service", "bar-widget"]` with
`keepLoaded: true`. That means the shell loads `Service.qml` **once** (it is
the single source of truth) and `Panel.qml` **once per monitor** (a bar widget
exists per bar). The panel copies never own state — they read from the service
via `bar.shell.serviceFor("dual_monitor_wallpaper")` — so the per-monitor
instances can never disagree.

---

## How it works

- **Wallpapers** live in one folder (default `~/.omarchy-config/wallpaper`).
  Each wallpaper is a **pair** of files sharing a stem: `forest_L.png` +
  `forest_R.png`. A file is a left file when its stem (name without extension)
  ends in `_L` and has a real name before it; same for `_R`.
- **Pair grouping** (`Model.pairs`): the folder is grouped into pairs by stem,
  sorted lexicographically. Index 0 is the pair that was applied before pairs
  existed (the lexicographically first one), so the very first run shows the
  same wallpaper as the original single-wallpaper behaviour.
- **Rendering**: the service creates one background `PanelWindow` **per
  screen** (the same per-screen layer Omarchy's stock background uses) and maps
  each screen to a side — from your explicit monitor choice, or by geometry
  (leftmost screen = left, rightmost = right) when you haven't chosen. Each
  window shows the wallpaper of its side.
- **Config** lives in the `dualWallpaper` block of
  `~/.config/omarchy/shell.json`:

  ```json
  {
    "dualWallpaper": {
      "wallpaperDir": "~/.omarchy-config/wallpaper",
      "leftMonitor": "HDMI-A-1",
      "rightMonitor": "eDP-1",
      "pairIndex": 0
    }
  }
  ```

  - `wallpaperDir` — folder holding the `*_L` / `*_R` files (`~` is expanded).
  - `leftMonitor` / `rightMonitor` — explicit Hyprland monitor names
    (`""` = fall back to geometry).
  - `pairIndex` — index into the sorted pair list; written by the Prev/Next
    controls so the current pair survives a restart.

- **Live updates**: a `FileView` watches the wallpaper folder, and a `find`
  re-scans it on every change, so dropping a new `*_L` / `*_R` file into the
  folder makes it appear immediately (and it becomes part of the pair list).

---

## Features

- Wallpaper folder, left monitor and right monitor configurable from the
  panel; changes apply live.
- Left/right by explicit monitor name, with a geometry fallback for the common
  two-monitor case.
- **Cycle through your pairs**: right-click the bar icon to jump to the **next**
  pair; the panel has **◀ / ▶** buttons to move back and forth (it wraps
  around). The current pair is remembered across restarts.
- Full IPC control (see [CLI](#cli)).

---

## Installation

`omarchy plugin add` only accepts a **git URL**, so for a local folder you copy
the plugin files into the plugins dir and enable it:

```bash
cp manifest.json Model.js Service.qml Panel.qml README.md \
   ~/.config/omarchy/plugins/dual_monitor_wallpaper/
omarchy plugin enable dual_monitor_wallpaper
omarchy plugin disable omarchy.background
omarchy restart shell
```

> **Disabling `omarchy.background` is required.** This plugin renders its
> per-screen wallpapers on the same background layer as Omarchy's stock
> background, so both cannot be active at once. Nothing else is touched.

If you install from a git URL instead:

```bash
omarchy plugin add <git-url> --enable
omarchy plugin disable omarchy.background
omarchy restart shell
```

Put your wallpaper pairs in the folder:

```bash
mkdir -p ~/.omarchy-config/wallpaper
cp /path/to/left.png  ~/.omarchy-config/wallpaper/forest_L.png
cp /path/to/right.png ~/.omarchy-config/wallpaper/forest_R.png
```

Verify:

```bash
omarchy plugin list
omarchy plugin validate ~/.config/omarchy/plugins/dual_monitor_wallpaper
omarchy-shell dualwallpaper status
```

---

## CLI

The IPC target is `dualwallpaper` (exposed by `Service.qml`):

```bash
omarchy-shell dualwallpaper status          # full state as JSON
omarchy-shell dualwallpaper dir             # print folder
omarchy-shell dualwallpaper dir <path>      # set folder
omarchy-shell dualwallpaper left            # print left monitor
omarchy-shell dualwallpaper left <name>     # set left monitor
omarchy-shell dualwallpaper right           # print right monitor
omarchy-shell dualwallpaper right <name>    # set right monitor
omarchy-shell dualwallpaper refresh         # rescan the folder
omarchy-shell dualwallpaper next            # next wallpaper pair
omarchy-shell dualwallpaper prev            # previous wallpaper pair
```

Monitor names are the ones Hyprland reports — see `hyprctl monitors`.

---

## Developing / modifying

These are the gotchas that cost time; read them before editing.

1. **Clear the QML cache after editing.** Quickshell compiles QML/JS to
   `~/.cache/quickshell/qmlcache/*.qmlc` and `*.jsc`. After changing any
   `.qml` or `.js`, clear it and restart, otherwise the shell keeps running the
   old compiled code:

   ```bash
   rm -rf ~/.cache/quickshell/qmlcache
   omarchy restart shell
   ```

   (`omarchy restart shell` alone is not enough if the cache is stale.)

2. **Define JS functions at the top level of `Model.js`.** Do **not** put a
   `function` *inside* `if (typeof module !== "undefined") { ... }`. In QML
   there is no `module`, so that block never runs — a function declared inside
   it is hoisted (the name exists) but has no body, and calling it throws
   `TypeError: Property 'X' of object [object Object] is not a function`.
   Keep all functions at the top level and only the `module.exports = { ... }`
   object inside the `if`.

3. **Config writes are not synchronously visible.** `mutateConfig` writes
   `shell.json` with `atomicWrites` and then re-reads the file via
   `applyConfigText`. The atomic write is not flushed at that point, so the
   re-read sees the *old* value. If a change must take effect immediately
   (e.g. `pairIndex`), set the property and recompute by hand right after
   `mutateConfig` rather than relying on the file round-trip.

4. **The bar widget exists once per monitor.** `Panel.qml` is instantiated per
   bar. It must only *read* from and *call into* the single service — never
   store its own copy of state — or the instances will disagree.

5. **Check the log for QML errors** after a restart:

   ```bash
   journalctl --user --no-pager | grep -iE 'dual|wallpaper' | grep -iE 'error|warn'
   ```

   (A harmless, expected warning is
   `IpcHandler ... another handler is registered for target dualwallpaper` —
   both `Panel.qml`'s base and `Service.qml` register a handler for the same
   target; the service's is the one used.)

---

## Troubleshooting

- **Icon shows "service not running" / IPC returns empty** — the service failed
  to load. Check the log above; the usual cause is a QML/JS error (see the
  developing notes) or a stale cache.
- **Wallpaper doesn't change after editing a file** — make sure the file name
  really ends in `_L` / `_R` and has a stem before it (`L.png` alone is ignored).
- **Both wallpapers show on one monitor** — set `leftMonitor` / `rightMonitor`
  explicitly in the panel; the geometry fallback only works for the common
  two-monitor, side-by-side layout.
- **Stock wallpaper reappears** — re-run `omarchy plugin disable omarchy.background`.

---

## License

MIT

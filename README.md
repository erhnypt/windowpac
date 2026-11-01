# WindowPac

Windows-style window management for macOS (Apple Silicon + Intel, macOS 14+).
Menu-bar app, no Dock icon.

## Shortcuts

Every shortcut can be changed in **menu bar icon → Settings… → Shortcuts** (click the button, press the new keys;
needs ⌘, ⌥ or ⌃; ⎋ cancels; ↺ resets). Defaults:

| Keys | Action |
|---|---|
| ⌘⌥ + ← / → | Snap to left / right half. Press again on a snapped window → continues to the next display |
| ⌘⌥ + ↑ | Fill the screen (maximize) |
| ⌘⌥ + ↓ | Restore previous size, otherwise minimize |
| ⌘⌥⇧ + ← / → | Move window to the previous / next display (keeps relative size) |
| ⌘⌥⇧ + ↑ / ↓ | Enter / exit native full screen (⌘⌥ + arrows also leave full screen first) |
| ⌥⇥ / ⌥⇧⇥ | Alt-Tab over **every window** on all displays and Spaces, including minimized ones, with live thumbnails (Screen Recording permission). Release ⌥ to switch, Esc to cancel |
| ⌃⌘V | Clipboard history: search, ↑↓ to select, ↩ or click to paste into the app you were in |

## Clipboard history

Copied text is recorded (up to 50 items by default, 10–200 in Settings), newest first, duplicates collapsed.
Items marked concealed/transient by password managers are never stored. By default the history is kept
on disk across restarts in `~/Library/Application Support/WindowPac/clipboard.json` (owner-only);
turn that off in Settings → Features to keep it in memory only.

## Battery widget

A small panel on the desktop (below windows, draggable, position remembered) shows the Mac's charge and
the charge of connected Bluetooth devices (mouse, keyboard, AirPods incl. L/R/case). Toggle in the menu.
It is **not** shown on the lock screen: macOS does not let third-party apps draw there.

## Build & install (on a Mac)

```sh
./scripts/build.sh          # universal arm64 + x86_64 → build/WindowPac.app
cp -R build/WindowPac.app /Applications/
open /Applications/WindowPac.app
```

Shortcuts are registered as system hotkeys (no keyboard event tap, so ordinary typing/Tab is never touched).
On first launch grant **Accessibility** (System Settings → Privacy & Security). After the
permission is granted WindowPac registers itself as a login item, so it starts automatically
from then on (toggle in the menu: "Launch at login").

## Notes / limitations

- Windows on *other Spaces* appear in the switcher with their app name (macOS only exposes
  titles with Screen Recording permission); selecting one switches to its Space.
- Run `./scripts/make-cert.sh` once before the first build: it creates a local signing identity so
  macOS keeps the permission grants across rebuilds (ad-hoc signing loses them each time).

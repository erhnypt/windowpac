# WindowPac

Windows-style window management for macOS (Apple Silicon + Intel, macOS 14+).
Menu-bar app, no Dock icon.

## Shortcuts

Default modifier is **⌘⌥** (changeable from the menu: ⌘⌥, ⌃⌥, ⌃⌘). Plain ⌥+Arrow is not used because it is word-jumping in text fields.

| Keys | Action |
|---|---|
| ⌘⌥ + ← / → | Snap to left / right half. Press again on a snapped window → continues to the next display |
| ⌘⌥ + ↑ | Fill the screen (maximize) |
| ⌘⌥ + ↓ | Restore previous size, otherwise minimize |
| ⌘⌥ + ⇧ + ← / → | Move window to the previous / next display (keeps relative size) |
| ⌘⌥ + ⇧ + ↑ / ↓ | Enter / exit native full screen |
| ⌥⇥ / ⌥⇧⇥ | Alt-Tab over **every window** on all displays and Spaces, including minimized ones. Release ⌥ to switch, Esc to cancel |

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

# WindowPac

Windows-style window management for macOS (Apple Silicon + Intel, macOS 14+).
Menu-bar app, no Dock icon.

## Language

English and Turkish. The default follows the system language; change it any time in the menu bar icon → **Language**
or Settings → Features → Language (takes effect immediately, no restart).

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

Copied **text, images and files** are recorded (up to 50 items by default, 10–200 in Settings; at most 15 images),
newest first, duplicates collapsed. Items marked concealed/transient by password managers, and anything copied while an
app from the **ignored apps** list (Settings → Clipboard; password managers by default) is in front, are never stored.
By default the history is kept on disk across restarts in `~/Library/Application Support/WindowPac/` (owner-only);
turn that off in Settings → Features to keep it in memory only.

**Pinning:** click the pin icon on an entry (or ⌘P on the selected one). Pinned entries stay at the top, are not
counted against the item limit, survive "Clear unpinned" and are always saved to disk, even when
"keep after restart" is off. Unpin an entry first to delete it.

**Snippets:** named notes you create in Settings → Clipboard. They sit at the top of the panel, are always saved and
never removed automatically.

## Alt-Tab extras

While the list is open: **W** closes the selected window, **Q** quits its app, **M** minimizes it (hold the same
modifier as the Alt-Tab shortcut). Hovering selects an entry and clicking switches to it.

## Hidden menu bar items

Choose in **Settings → Menu bar** which menu bar **icons** to hide (each icon is listed as it looks in the bar; an app
with several icons gets one entry per icon). The chosen icons are covered with a capture of the
real menu bar background (all icons excluded, so it needs the Screen Recording permission; without it a plain dark
patch is used) and move into a Control Center–style card that drops down from WindowPac's **⌄** button (or ⌃⌘B).
Click an icon in the card to open its menu: WindowPac presses the real status item through Accessibility (falling
back to a brief real click). The gap where an icon was stays, macOS offers no way to close it. Apple's own items
(Wi-Fi, battery, clock) can't be hidden this way. Hidden Bar's "huge status item pushes icons away" trick no longer
works on current macOS.

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

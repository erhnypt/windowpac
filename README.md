# WindowPac

Windows-style window management for macOS (Apple Silicon + Intel, macOS 14+).
Menu-bar app, no Dock icon.

## Shortcuts

Default modifier is **⌥** (the Windows-key equivalent; changeable from the menu: ⌥, ⌃⌥, ⌃⌘, ⌥⌘).
When keyboard focus is in a text field the arrows pass through untouched, so ⌥+← word-jumping still works there.

| Keys | Action |
|---|---|
| mod + ← / → | Snap to left / right half. Press again on a snapped window → continues to the next display |
| mod + ↑ | Fill the screen (maximize) |
| mod + ↓ | Restore previous size, otherwise minimize |
| mod + ⇧ + ← / → | Move window to the previous / next display (keeps relative size) |
| mod + ⇧ + ↑ / ↓ | Enter / exit native full screen |
| ⌥⇥ / ⌥⇧⇥ | Alt-Tab over **every window** on all displays and Spaces, including minimized ones. Release ⌥ to switch, Esc to cancel |

## Build & install (on a Mac)

```sh
./scripts/build.sh          # universal arm64 + x86_64 → build/WindowPac.app
cp -R build/WindowPac.app /Applications/
open /Applications/WindowPac.app
```

On first launch grant **Accessibility** (System Settings → Privacy & Security). After the
permission is granted WindowPac registers itself as a login item, so it starts automatically
from then on (toggle in the menu: "Launch at login").

## Notes / limitations

- Windows on *other Spaces* appear in the switcher with their app name (macOS only exposes
  titles with Screen Recording permission); selecting one switches to its Space.
- Run `./scripts/make-cert.sh` once before the first build: it creates a local signing identity so
  macOS keeps the permission grants across rebuilds (ad-hoc signing loses them each time).

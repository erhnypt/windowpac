# WindowPac

Windows-style window management for macOS (Apple Silicon + Intel, macOS 13+).
Menu-bar app, no Dock icon.

## Shortcuts

Default modifier is **⌃⌥** (changeable from the menu: ⌃⌥, ⌃⌘, ⌥⌘).
Plain ⇧+Arrow is deliberately not used: every text field uses it for selection.

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
- Rebuilding with ad-hoc signing may make macOS ask for the Accessibility grant again;
  set `SIGN_ID` to a developer identity to avoid that.

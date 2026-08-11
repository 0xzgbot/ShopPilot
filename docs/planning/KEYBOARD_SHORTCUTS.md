# ShopPilot — Keyboard Shortcuts Reference

> Native macOS CNC suite · SwiftUI (macOS 14+) · Apple HIG compliant

---

## Standard macOS Shortcuts

| Shortcut | Action | Context |
| --- | --- | --- |
| `⌘ N` | New file / job | Global |
| `⌘ O` | Open existing file or project | Global |
| `⌘ S` | Save current file or job | Global |
| `⇧ ⌘ S` | Save As… | Global |
| `⌘ W` | Close current window / tab | Global |
| `⌘ Q` | Quit ShopPilot | Global |
| `⌘ Z` | Undo last action | Global |
| `⇧ ⌘ Z` | Redo last undone action | Global |
| `⌘ C` | Copy selected item(s) | Design / UI |
| `⌘ V` | Paste from clipboard | Design / UI |
| `⌘ X` | Cut selected item(s) | Design / UI |
| `⌘ A` | Select all items in current view | Design / UI |
| `⌘ D` | Duplicate selected item(s) | Design / UI |
| `⌫ Delete` | Delete selected item(s) | Design / UI |
| `⌘ F` | Find and replace text | Global |
| `⌘ H` | Hide ShopPilot | Global |
| `⌘ M` | Minimize current window | Global |
| `⌘ ,` | Open Settings… | Global |
| `⌘ I` | Show Inspector / Properties panel | Design / Machine |
| `⌘ 0–9` | Switch to tab or stage (1 = Stage 1, etc.) | Global |

---

## CNC Machine Shortcuts

> Available when a machine session is active (simulator or real controller).

| Shortcut | Action | Context |
| --- | --- | --- |
| `Space` | Play / Pause toolpath simulation | Simulation view |
| `⇧ Space` | Stop simulation and reset to start | Simulation view |
| `H` | Home all axes (send G28) | Machine panel |
| `R` | Reset machine state and clear alarms | Machine panel |
| `⌘ R` | Restart / re-post current toolpath | Job console |
| `!` (exclamation) | Send hold signal to controller (GRBL: `!`) | Machine panel |
| `~` (tilde) | Resume from hold state (GRBL: `~`) | Machine panel |
| `⌘ E` | Emergency stop — halt all motion immediately | Global chrome |
| `⇧ ⌘ H` | Toggle jog wheel / directional pad visibility | Machine panel |

---

## Design Tool Shortcuts

> Available in the 2D/3D design canvas. The active tool is selected by shortcut; clicking elsewhere or pressing Escape deselects.

| Shortcut | Action | Context |
| --- | --- | --- |
| `V` | Select / move tool | Canvas |
| `L` | Draw line (straight segment) | Canvas |
| `C` | Draw circle (center + radius) | Canvas |
| `R` | Draw rectangle (corner to corner) | Canvas |
| `T` | Add text object | Canvas |
| `P` | Draw polyline / freehand path | Canvas |
| `A` | Align selected objects (opens align options) | Canvas |
| `G` | Group selected items | Canvas |
| `⇧ ⌘ G` | Ungroup selected items | Canvas |
| `⌘ Shift + [` | Send selection backward in z-order | Canvas |
| `⌘ Shift + ]` | Bring selection forward in z-order | Canvas |
| `D` | Duplicate and offset selected item(s) | Canvas |
| `⌘ 1`…`⌘ 6` | Jump to stage: Setup / Design / Model / Cut / Preview / Machine | Global |
| `⌘ K` | Command palette | Global |
| `⌘ ⇧ P` | Command palette (alternative) | Global |
| `⌘ ⌥ 1`…`⌘ ⌥ 3` | View presets: top / isometric / front (gizmo) | Preview / Model |

> All menu-bar shortcuts are **user-remappable** — Preferences → Menu Shortcuts (SPK-1317). The table above shows the defaults.

---

## Navigation Shortcuts

> Apply to the canvas viewport, preview pane, and file browser.

| Shortcut | Action | Context |
| --- | --- | --- |
| `⌘ 0` | Fit all content to screen | Canvas / Preview |
| `⌘ +` (plus) | Zoom in | Canvas / Preview |
| `⌘ -` (minus) | Zoom out | Canvas / Preview |
| `⌘ =` (equals) | Zoom in (alternative) | Canvas / Preview |
| `⌘ 1` | Zoom to 100% (actual size) | Canvas / Preview |
| `⌘ Option 0` | Fit width to screen | Canvas / Preview |
| Scroll wheel / pinch | Zoom at cursor position | Canvas / Preview |
| Space + drag | Pan viewport (hand tool) | Canvas / Preview |
| `⌘ Option I` | Invert zoom direction (accessibility) | Global |

---

## Modifier Conventions

| Modifier | Meaning in ShopPilot |
| --- | --- |
| `⇧ Shift` + drag | Constrain to horizontal, vertical, or 45° angle |
| `⌥ Option` + click | Sample color / probe coordinate without committing |
| `⌘ Cmd` + drag | Duplicate while moving (clone) |
| `⌃ Control` + click | Show contextual menu (right-click equivalent) |

---

## Notes

- All shortcuts follow **Apple Human Interface Guidelines** for macOS.
- Shortcuts are discoverable via the **⌘ K Command Key Lookup** sheet.
- CNC machine shortcuts require an active session; they are disabled when disconnected.
- Design tool shortcuts use single-letter mnemonics matching common CAD conventions (V = select, L = line, C = circle, T = text).
- No shortcut conflicts with macOS system-level shortcuts.

---

*Last updated: 2026-07-28 · ShopPilot v1.0 planning*

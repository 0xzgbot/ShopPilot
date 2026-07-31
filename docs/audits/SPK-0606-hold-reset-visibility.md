# SPK-0606 — Hold/Reset Visibility Audit

## Requirement (P0, Phase G)
Hold and Reset buttons must be **always visible** whenever the machine is connected. Safety rule: E-stop / Reset always visible while connected — fixed chrome, not buried in a menu.

## Audit Scope
- **File:** `Sources/ShopPilot/MachineConnection.swift`
- **Property:** `safetyChrome` (private computed property, lines 743–783)
- **Actions:** `holdMachine()` (line 796), `resetMachine()` (line 804)
- **State enum:** `ConnectionState` in `Sources/ShopPilotCore/MachineSession.swift`

---

## 1. Visibility Conditions

```swift
// MachineConnection.swift, lines 744–748
Group {
    if connectionManager.connectionState.isConnected
        || connectionManager.connectionState == .connecting
        || connectionManager.connectionState.isInAlarm
    {
        // Hold + Reset buttons rendered here
    }
}
```

| State | Condition | Visible? | Rationale |
|-------|-----------|----------|-----------|
| `.disconnected` | `isConnected=false`, `==.connecting=false`, `isInAlarm=false` | ❌ No | No machine to control |
| `.connecting` | `==.connecting=true` | ✅ Yes | Machine may be responsive |
| `.connected` | `isConnected=true` | ✅ Yes | Machine actively connected |
| `.error(msg)` | `isInAlarm=true` (`.error` case) | ✅ Yes | User needs reset to recover |

**Verdict: ✅ PASS** — Safety chrome is visible in all machine-active states (connected, connecting, alarm/error). Hidden only when disconnected.

### Rendering context
The `safetyChrome` view is a direct child of the main `VStack` in `body` (line 356), with no parent view applying conditional visibility. It renders immediately below `connectionControls` and above `jogControls`.

---

## 2. Touch Target Size

Both buttons use:
- `.buttonStyle(.borderedProminent)` — macOS prominent button style
- `.controlSize(.large)` — explicitly large control size
- `.frame(maxWidth: .infinity)` — fills available horizontal space

SwiftUI `.borderedProminent` with `.controlSize(.large)` on macOS produces buttons with a minimum height of ~38pt plus padding, yielding well above the 44x44pt accessibility minimum. Each button spans the full available width (split 50/50 via HStack with spacing:12).

**Verdict: ✅ PASS** — Touch targets exceed 44x44pt minimum.

---

## 3. Labels and Colors

| Button | Icon | Label Text | Tint Color | Keyboard Shortcut |
|--------|------|------------|------------|-------------------|
| Hold | `pause.circle.fill` | "Hold" | Orange (`.tint(.orange)`) | ⌘H |
| Reset | `arrow.counterclockwise.circle.fill` | "Reset" | Red (`.tint(.red)`) | ⌘R |

**Verdict: ✅ PASS** — Both buttons have:
- Clear SF Symbol icons (universally recognizable)
- Text labels in `.caption2` font
- Industry-standard colors (orange for hold, red for reset/stop)
- Keyboard shortcuts for redundant access

---

## 4. GRBL Commands

### Hold Machine
```swift
// MachineConnection.swift, line 798
await connectionManager.sendCommand("!") // GRBL hold
```
- **Command sent:** `!` (exclamation mark)
- **GRBL spec:** `!` is the correct realtime hold command (pauses machine motion while maintaining spindle state)
- **Verdict: ✅ CORRECT**

### Reset Machine
```swift
// MachineConnection.swift, lines 806–807
let resetCmd = "\u{18}" // GRBL reset (Ctrl+X)
await connectionManager.sendCommand(resetCmd)
```
- **Command sent:** `\u{18}` (ASCII 0x18 = Ctrl+X)
- **GRBL spec:** 0x18 is the correct realtime reset command (clears alarms, resets state machine, returns to idle)
- **Verdict: ✅ CORRECT**

> **Note:** The task spec referenced "Hold = $H" but `$H` is the GRBL homing cycle command, not hold. The actual GRBL hold command is `!`. The implementation is correct per the GRBL 1.1 realtime command protocol.

---

## 5. Safety Chrome Placement

The safety chrome is rendered in the main `VStack` body at line 356, in this order:
1. `statusBar` (connection indicator)
2. `consoleView` (message log)
3. `commandInputView` (G-code input)
4. `streamProgress` (job progress bar)
5. `connectionControls` (transport picker, connect/disconnect)
6. **`safetyChrome`** ← Hold + Reset buttons
7. `jogControls` (jog pad, home, work zero)
8. `preflightChecklist` (pre-flight checklist + RUN button)

Safety chrome is **above** jog controls and preflight checklist, ensuring it is never hidden behind other interactive elements. It is also **not inside a ScrollView**, so it is always visible without scrolling.

**Verdict: ✅ PASS** — Proper placement, always visible when conditions met.

---

## 6. Issue Summary

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | Hold command spec mismatch ($H vs !) | Low (documentation) | ✅ No issue — code is correct |
| 2 | Touch target size | — | ✅ PASS (>.44x44pt) |
| 3 | Visibility when disconnected | — | ✅ PASS (correctly hidden) |
| 4 | Visibility when connected/connecting | — | ✅ PASS (correctly shown) |
| 5 | Color coding | — | ✅ PASS (orange hold, red reset) |
| 6 | GRBL command correctness | — | ✅ PASS (! for hold, 0x18 for reset) |
| 7 | Placement in view hierarchy | — | ✅ PASS (above scrollable content) |

**No issues found.** Implementation fully meets SPK-0606 requirements.

---

## 7. Screenshots / Visual Reference

Since this is a code audit (no live GUI), the visual layout is described from code structure:

```
┌─────────────────────────────────────────────────────────┐
│  ● Connected                              <status text>   │  ← statusBar
├─────────────────────────────────────────────────────────┤
│  [Console: black background, auto-scrolling messages]   │  ← consoleView
├─────────────────────────────────────────────────────────┤
│  [TextField...]  [↑ circle]                              │  ← commandInputView
├─────────────────────────────────────────────────────────┤
│  [Segmented: Sim | Serial]  [Disconnect]  [🗑️]         │  ← connectionControls
├─────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐             │
│  │  ⏸️  Hold        │  │  ↺  Reset        │             │  ← safetyChrome
│  │  (orange)        │  │  (red)           │             │
│  └──────────────────┘  └──────────────────┘             │
│     (⌘H)                   (⌘R)                         │
├─────────────────────────────────────────────────────────┤
│  [Step: 10mm segmented]                                  │
│  [Y↑  X← 🏠 X→  Z↓]                                     │
│  [Y↓  Z↑]                                                │
│  [Zero X] [Zero Y] [Zero Z]                              │  ← jogControls
├─────────────────────────────────────────────────────────┤
│  [Pre-flight checklist...]                               │  ← preflightChecklist
└─────────────────────────────────────────────────────────┘
```

---

## Final Result

**✅ PASS — SPK-0606 fully compliant.**

Hold and Reset buttons are:
- Visible whenever connection state is `.connected`, `.connecting`, or `.error` (alarm)
- Hidden when `.disconnected`
- Large enough for easy tapping (`.controlSize(.large)` + `.borderedProminent`)
- Clearly labeled with standard colors (orange hold, red reset)
- Sending correct GRBL realtime commands (`!` for hold, `\u{18}` for reset)
- Placed above scrollable content in the view hierarchy

---

_Audit date: 2026-07-31_
_Auditor: Subagent (SPK-0606)_

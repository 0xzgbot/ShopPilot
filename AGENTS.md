# ShopPilot — Agent Operating Manual (Living Document)

> **Point any local Hermes (or other) agent at this file to begin work.**  
> Single source of truth for *what to build*, *stack*, *order*, *safety rules*, and *how to update status*.

| Field | Value |
| --- | --- |
| **Project root** | `~/Desktop/ShopPilot` |
| **Working name** | ShopPilot |
| **Product class** | Native **macOS CNC suite**: Aspire-class **design + toolpaths + preview** + **machine control** |
| **Primary machines** | CNC routers (GRBL / FluidNC class controllers over USB serial); laser later |
| **Stack** | **SwiftUI** (macOS 14+) · geometry/toolpath core · Metal preview · serial IOKit/ORSSerialPort |
| **Not in first ship** | Illegal reverse-engineering of proprietary CRV; Windows/Linux ports |
| **Doc status** | Living — agents **must** update task checkboxes + Work log |
| **Last updated** | 2026-08-04 |
| **Current phase focus** | Lean CNC bar (G-code, V-Carve, 3D carving, GRBL control) — see LEAN_CNC_SCOPE |
| **★ Lean north star** | [`docs/planning/LEAN_CNC_SCOPE.md`](./docs/planning/LEAN_CNC_SCOPE.md) — **overrides Aspire feature-count parity** |
| **★ Single task board** | [`MASTER_KANBAN.md`](./MASTER_KANBAN.md) — **only** place to claim work |
| **★ Finish roadmap** | [`docs/planning/FINISH_ROADMAP.md`](./docs/planning/FINISH_ROADMAP.md) — Tracks 1–6 + lean 3D |
| **Legacy boards** | `HERMES_BUILD_TODO.md`, `HERMES_STUDIO_TODO.md` — superseded (reference only) |
| **Aspire reimagined plan** | [`docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md`](./docs/planning/ASPIRE_REIMAGINED_PRODUCT_PLAN.md) — vision/reference |
| **Market pain research** | [`docs/planning/ASPIRE_INGESTION_AND_MARKET_RESEARCH.md`](./docs/planning/ASPIRE_INGESTION_AND_MARKET_RESEARCH.md) |
| **Parity matrix** | [`docs/planning/FEATURE_PARITY_MATRIX.md`](./docs/planning/FEATURE_PARITY_MATRIX.md) — evidence; `[-]` = lean non-goal |
| **Planning notes** | [`docs/planning/`](./docs/planning/) |

---

## 0. How to use this document (agents)

### 0.1 Startup protocol

1. Read **§1 Mission**, **§2 Non-negotiables (safety)**, **§3 Architecture**, **§4 Agent roles**.
2. Read **[`docs/planning/LEAN_CNC_SCOPE.md`](./docs/planning/LEAN_CNC_SCOPE.md)** — product bar; skip cloud/social/video/gadget work.
3. Read **[`docs/planning/FINISH_ROADMAP.md`](./docs/planning/FINISH_ROADMAP.md)** — finish order (lean 3D may run before full Track 5).
4. Open **[`MASTER_KANBAN.md`](./MASTER_KANBAN.md)** — **only** task board. Prefer **SPK-1100–1106** spine, then lean 3D / V-Carve quality P0s; skip rows marked `[-]`.
5. Claim: `[ ]` → `[~]`, append Work log in MASTER_KANBAN.md.
6. Implement **Engine + UI + Persist + Verify** for the card (build-only is not done).
7. Mark `[x]`, Work log exit. If `[!]`, pick next Ready card — **never idle**.
8. **Never mark `[x]` if Engine/UI/Persist/Verify incomplete.**
9. Do not invent scope outside MASTER_KANBAN; add cards there if needed.
10. Dual-side / rotary / laser / Post Studio / App Store wait for Track 5 (**SPK-0623**). **STL → heightfield → 3D rough/finish G-code does not wait** (lean bar).

### 0.2 Status legend

| Mark | Meaning |
| --- | --- |
| `[ ]` | Not started |
| `[~]` | In progress |
| `[x]` | Done |
| `[!]` | Blocked on **true human-only** action (hardware purchase, App Store account, physical machine access) |
| `[-]` | Cancelled / deferred (note why) |

### 0.3 Parallelism

- **`// parallel-ok`** — may run concurrent with other parallel-ok tasks in-phase.
- **`deps: [ID,…]`** — all deps must be `[x]` before start.
- Prefer vertical slices when one agent owns a full epic (e.g. serial + parser + UI status).

### 0.4 Default ownership

| Agents always own | Humans only own |
| --- | --- |
| All code, tests, Xcode project, CI scaffolding | Physical machine wiring / e-stop hardware install |
| Simulator, fixtures, docs, UI copy | Final legal product name / trademark filing |
| Safety **software** interlocks & warnings | Accepting liability for live cuts on metal/wood |
| Packaging scripts, notarization **config** | Apple Developer account credentials & payment |
| Research notes on GRBL dialects | Buying USB adapters / routers |

---

## 1. Mission

Build **ShopPilot**: a Mac-native **Aspire-class** creative CNC suite **plus** integrated machine control.

### Track A — Machine Control (existing board)
1. Plug in a **CNC router** (USB serial GRBL/FluidNC-class).
2. Connection status, jog/home/zero, stream G-code, hold/resume/reset, console.
3. Simulator-first development.

### Track B — Studio / CAM (Aspire reimagined)
1. Job setup (single → double → rotary).
2. 2D design (vectors, text, bitmaps, layers, nest).
3. 3D components (combine modes, shapes, sculpt, import).
4. Full toolpath strategy set (profile → V-carve → 3D → specialty → laser).
5. Accurate preview simulation + posts + job sheets.
6. **Stage-rail UI**: full power, no permanent icon walls (see UX plan).

**Capability bar:** Vectric Aspire V12 feature surface (independently implemented).  
**UX bar:** progressive disclosure — every feature reachable via stage, overflow, recipe, or ⌘K — not via clutter.

---

## 2. Non-negotiables (safety)

These are product requirements, not nice-to-haves.

1. **E-stop / Reset always visible** while connected — fixed chrome, not buried in a menu.
2. **No auto-start streaming** on file open; explicit **Start** after user review.
3. **Disconnect / port error** → stop stream, surface alarm, do not silently retry mid-cut without user action.
4. **Soft-limit awareness** for jog UI when profile travel is known; warn if unknown.
5. **Spindle / coolant** commands only via explicit controls (no accidental M3 on connect).
6. Console must show **raw TX/RX** (toggle) for diagnosis.
7. Document: **software is not a substitute for a hardware e-stop.**
8. Unit tests for parser + streamer state machine **before** claiming live serial done.
9. Never ship default baud/port that auto-connects and runs a job on launch.

---

## 3. Architecture (target)

```
┌─────────────────────────────────────────────────────────────┐
│  ShopPilot.app (SwiftUI)                                    │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ Connection  │  │ Job Console  │  │ Machine Panel      │  │
│  │ Port picker │  │ G-code load  │  │ Jog / Home / WCS   │  │
│  │ Profiles    │  │ Stream ctrl  │  │ Spindle (manual)   │  │
│  └──────┬──────┘  └──────┬───────┘  └─────────┬──────────┘  │
│         │                │                    │             │
│  ┌──────▼────────────────▼────────────────────▼──────────┐  │
│  │              AppState / MachineSession                 │  │
│  └──────┬────────────────┬────────────────────┬──────────┘  │
│         │                │                    │             │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────────▼─────────┐  │
│  │ SerialPort  │  │ GCodeStream │  │ StatusParser       │  │
│  │ (IOKit)     │  │ + planner   │  │ (?, ok, alarm,     │  │
│  │ Simulator   │  │ hold/resume │  │  MPos, buffer)     │  │
│  └─────────────┘  └─────────────┘  └────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Module map

| Target | Responsibility |
| --- | --- |
| `ShopPilot` | App entry, SwiftUI scenes |
| `ShopPilotCore` | Session, streamer, profiles, G-code model (no UI) |
| `ShopPilotSerial` | Port enumeration, read/write, simulator transport |
| `ShopPilotGeometry` | Vector kernel, text, boolean ops, nesting |
| `ShopPilotTests` | Unit tests for parser, streamer, geometry, toolpaths |

### 3.2 Protocols first

```swift
protocol MachineTransport: AnyObject, Sendable {
    var events: AsyncStream<TransportEvent> { get }
    func open(config: SerialConfig) async throws
    func close() async
    func write(_ data: Data) async throws
}
```

Implementations: `SerialTransport`, `SimulatorTransport`.

### 3.3 GRBL dialect (v1)

- Status query: `?` → `<Idle|MPos:…|WPos:…|FS:…>` style parsing (tolerant).
- Streaming: line-based **ok-wait** mode first (safer); char-count later.
- Realtime: `0x18` reset, `!` hold, `~` resume, `?` status.
- Alarms: surface `ALARM:` / `error:` strings in UI banner.

---

## 4. Agent roles

| Role | Owns |
| --- | --- |
| **Architect** | Module boundaries, protocols, safety state machine |
| **Core engineer** | Streamer, parser, profiles, G-code model |
| **Serial engineer** | IOKit/ORSSerial, permissions, simulator |
| **UI engineer** | SwiftUI panels, accessibility, keyboard shortcuts |
| **QA** | Tests, fixtures under `fixtures/gcode/`, smoke scripts |
| **Tech writer** | README, safety copy, user runbook |

---

## 5. Repo layout

```
ShopPilot/
  AGENTS.md                 ← this file
  HERMES_BUILD_TODO.md      ← master checklist for Hermes
  README.md
  docs/planning/            ← ADRs, research, open questions
  Sources/                  ← Swift packages / app sources
  Tests/
  fixtures/gcode/           ← sample jobs (air-cut safe paths)
  scripts/                  ← build, format, simulator helpers
  research/                 ← GRBL notes, controller matrices
```

---

## 6. Definition of Done (MVP)

- [ ] Xcode project builds on Apple Silicon Mac without agent-introduced fatal warnings
- [ ] Unit tests green for status parser + streamer state machine
- [ ] Simulator path: connect → home (sim) → load fixture → stream → hold → resume → complete
- [ ] UI: connection, console, jog, job controls, always-on hold/reset
- [ ] Machine profile save/load (JSON in Application Support)
- [ ] README: how to run, how to connect a real GRBL router, safety disclaimer
- [ ] No secrets committed; no auto-run on launch

---

## 7. Human-only blockers (mark `[!]`)

- Access to a physical CNC router for live integration test
- Apple Developer Program for notarized distribution (optional for local build)
- Confirm exact controller firmware (GRBL 1.1 vs FluidNC vs other) on user’s machine

---

## 8. Work log protocol

Append to `HERMES_BUILD_TODO.md` § Work log:

```
### YYYY-MM-DD — agent/role
- Claimed: SP-xxx
- Did: …
- Result: [x] / blocked reason
```

---

## 9. Hand-off prompt (copy for Hermes)

```
You are building ShopPilot at ~/Desktop/ShopPilot.
North star: docs/planning/LEAN_CNC_SCOPE.md (offline G-code / V-Carve / 3D carving / GRBL).
Board: MASTER_KANBAN.md. Finish order: docs/planning/FINISH_ROADMAP.md.
Read AGENTS.md safety. No Vectric proprietary assets. No cloud/social/in-app video.
DoD: Engine + UI + Persist + Verify — never mark [x] for build-only/file-drop.
Prefer SPK-1100–1106, lean 3D/V-Carve quality, then open P0 — skip [-] non-goals.
Loop: claim → implement full AC → [x] + work log → repeat.
Lean 3D rough/finish may ship before SPK-0623. Never idle on [!] — next Ready card.
```

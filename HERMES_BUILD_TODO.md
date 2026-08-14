# ShopPilot — Hermes Master Build Todo

> ⚠️ **SUPERSEDED** by [`MASTER_KANBAN.md`](./MASTER_KANBAN.md).  
> Do **not** claim new work here. Kept for ID history / crosswalk only.

**Project root:** `~/Desktop/ShopPilot`  
**Operating manual:** [`AGENTS.md`](./AGENTS.md)  
**Last updated:** 2026-07-28  
**Phase focus:** Phase 0–1 bootstrap + core domain  
**Related Studio pain items:** [`HERMES_STUDIO_TODO.md`](./HERMES_STUDIO_TODO.md) Wave **PAIN-7** (machine handoff) + **PAIN-1** (native Mac serial)

Agents: claim with `[~]`, finish with `[x]`, human-only with `[!]`, defer with `[-]`.  
Respect `deps`. Items marked `// parallel-ok` may run concurrently within the same phase.

---

## Status legend

| Mark | Meaning |
| --- | --- |
| `[ ]` | Not started |
| `[~]` | In progress |
| `[x]` | Done |
| `[!]` | Human-only blocker |
| `[-]` | Cancelled / deferred |

---

## Critical path

```
SP-000 → SP-001 → SP-200 → SP-201 → SP-108 → SP-202 → SP-301/305 → SP-505 → SP-506
```

## Agent waves

| Wave | Tasks | Notes |
| --- | --- | --- |
| **W0** | SP-000…SP-005, SP-003, SP-004 | Bootstrap |
| **W1** | SP-100–108, SP-200–202 | Core + simulator |
| **W2** | SP-203–206, SP-300–310 | Serial + UI |
| **W3** | SP-400–405, SP-500–505 | Features + harden |
| **W4** | SP-506 | Live hardware (human) |
| **W5** | SP-600+ | Post-MVP only |

---

## Phase 0 — Project bootstrap

- [ ] **SP-000** Scaffold Xcode / SPM macOS app `ShopPilot` (SwiftUI lifecycle, bundle id e.g. `local.shoppilot.app`)  
  - **Role:** Core · **deps:** none · **// parallel-ok**  
  - **AC:** App launches empty window on Apple Silicon via Xcode or `xcodebuild`

- [ ] **SP-001** Create `ShopPilotCore`, `ShopPilotSerial`, `ShopPilotTests` targets; wire dependencies  
  - **Role:** Architect · **deps:** SP-000  
  - **AC:** Core has no UI imports; tests target links Core (+ Serial as needed)

- [ ] **SP-002** Repo hygiene: `.gitignore` (Xcode, DerivedData, `.DS_Store`), license placeholder  
  - **Role:** Tech writer · **deps:** SP-000 · **// parallel-ok**  
  - **AC:** Ignore rules prevent committing build artifacts

- [ ] **SP-003** Write `docs/planning/ADR-001-stack.md` (SwiftUI + serial rationale)  
  - **Role:** Tech writer · **deps:** none · **// parallel-ok**  
  - **AC:** ADR explains alternatives rejected (Electron, Tauri, Python)

- [ ] **SP-004** Sample fixtures under `fixtures/gcode/` (square air-path, rapid-only, long-line stress) with “SIM ONLY / verify travel” comments  
  - **Role:** QA · **deps:** none · **// parallel-ok**  
  - **AC:** ≥3 `.nc`/`.gcode` files loadable as text

- [ ] **SP-005** `scripts/build.sh` + `scripts/test.sh` for non-interactive agent use  
  - **Role:** Core · **deps:** SP-000, SP-001  
  - **AC:** Scripts exit 0 on clean build/test

---

## Phase 1 — Core domain (no hardware)

- [ ] **SP-100** `SerialConfig` + `MachineProfile` models (name, baud, data/parity/stop, port pattern, travel mm, max feed, spindle max, stream mode, useSimulator)  
  - **Role:** Core · **deps:** SP-001 · **// parallel-ok**  
  - **AC:** Codable models with sensible defaults (115200 8N1)

- [ ] **SP-101** Profile persistence to Application Support JSON  
  - **Role:** Core · **deps:** SP-100  
  - **AC:** Save/load/delete round-trip unit test

- [ ] **SP-102** G-code file model: load URL, optional comment strip, normalize lines, counts, basic XY/Z bounds from G0/G1  
  - **Role:** Core · **deps:** SP-001 · **// parallel-ok**  
  - **AC:** Loads `fixtures/gcode/*`; reports line count > 0

- [ ] **SP-103** `StatusParser` for GRBL-like `<Idle|Run|Hold|Alarm|…>` + MPos/WPos/FS/Ov (tolerant)  
  - **Role:** Core · **deps:** SP-001 · **// parallel-ok**  
  - **AC:** Pure functions; no serial dependency

- [ ] **SP-104** Unit tests: StatusParser goldens (idle, run, alarm, hold, partial lines, noise)  
  - **Role:** QA · **deps:** SP-103  
  - **AC:** Tests fail on parser regressions

- [ ] **SP-105** `GCodeStreamer` state machine: Idle → Streaming → Hold → Streaming → Completed | Faulted; ok-wait  
  - **Role:** Core · **deps:** SP-102  
  - **AC:** Explicit start required; documented states

- [ ] **SP-106** Realtime command API: reset `0x18`, hold `!`, resume `~`, status `?` (not mixed into line queue)  
  - **Role:** Core · **deps:** SP-105  
  - **AC:** Realtime bytes bypass line buffer

- [ ] **SP-107** Unit tests: streamer transitions, mid-job hold, transport fault, no implicit start  
  - **Role:** QA · **deps:** SP-105, SP-106  
  - **AC:** Green in CI/script

- [ ] **SP-108** `MachineSession` façade: connect/disconnect, send line, status poll 1–10 Hz, surface alarms  
  - **Role:** Core · **deps:** SP-103, SP-105, SP-106  
  - **AC:** UI can bind to session without knowing transport details

---

## Phase 2 — Transport layer

- [ ] **SP-200** `MachineTransport` protocol + `TransportEvent` (bytesIn/Out, opened, closed, error)  
  - **Role:** Serial · **deps:** SP-001  
  - **AC:** Protocol usable from Core without UI

- [ ] **SP-201** `SimulatorTransport`: fake GRBL (`ok`, `?` status, accept G-code, configurable delay)  
  - **Role:** Serial · **deps:** SP-200  
  - **AC:** Completes a short job without hardware

- [ ] **SP-202** Simulator integration test: open → status → stream fixture → hold → resume → complete  
  - **Role:** QA · **deps:** SP-108, SP-201  
  - **AC:** Automated test green

- [ ] **SP-203** Real serial: enumerate USB serial ports (`cu.*` / `tty.*`) via IOKit or ORSSerialPort  
  - **Role:** Serial · **deps:** SP-200 · **// parallel-ok** with SP-201  
  - **AC:** Returns list (may be empty without devices)

- [ ] **SP-204** Real serial open/read/write; baud config; clean close; background reader  
  - **Role:** Serial · **deps:** SP-203  
  - **AC:** Loopback or documented manual check procedure

- [ ] **SP-205** macOS serial permission notes + first-run UX copy (README + in-app)  
  - **Role:** Tech writer · **deps:** SP-203 · **// parallel-ok**  
  - **AC:** User can follow steps without agent help

- [ ] **SP-206** Transport factory: Simulator vs Serial from profile `useSimulator`  
  - **Role:** Core · **deps:** SP-201, SP-204  
  - **AC:** Single switch in profile/UI

---

## Phase 3 — SwiftUI application shell

- [ ] **SP-300** App chrome: 3-zone layout (machines / job / machine panel)  
  - **Role:** UI · **deps:** SP-000  
  - **AC:** Window usable at 1280×800

- [ ] **SP-301** **Safety chrome:** persistent Feed Hold + Reset (disabled when disconnected); document shortcuts  
  - **Role:** UI · **deps:** SP-108, SP-300  
  - **AC:** Controls always visible while connected

- [ ] **SP-302** Connection view: port picker, baud, Connect/Disconnect, simulator toggle, last error  
  - **Role:** UI · **deps:** SP-206, SP-300  
  - **AC:** Can connect to simulator from UI

- [ ] **SP-303** Status strip: state, MPos, WPos, feed/spindle if present, red alarm banner  
  - **Role:** UI · **deps:** SP-108, SP-300  
  - **AC:** Updates while connected without freezing UI

- [ ] **SP-304** Console: scrolling TX/RX, filter, copy, auto-scroll  
  - **Role:** UI · **deps:** SP-300 · **// parallel-ok**  
  - **AC:** Shows simulated traffic

- [ ] **SP-305** Job panel: Open G-code, progress, Start / Pause / Resume / Stop-Reset, confirm before Start  
  - **Role:** UI · **deps:** SP-108, SP-300  
  - **AC:** Full job cycle on simulator from UI

- [ ] **SP-306** Jog panel: XYZ ± step sizes, Home soft, disabled while streaming  
  - **Role:** UI · **deps:** SP-108, SP-300  
  - **AC:** Sends expected jog/home commands to simulator

- [ ] **SP-307** Profile editor UI (save/load/delete)  
  - **Role:** UI · **deps:** SP-101, SP-300  
  - **AC:** Profiles survive app relaunch

- [ ] **SP-308** Simple 2D XY path preview from G0/G1 (not full CAM)  
  - **Role:** UI · **deps:** SP-102, SP-305  
  - **AC:** Fixture square visible as polyline

- [ ] **SP-309** Keyboard shortcuts + accessibility labels for critical controls  
  - **Role:** UI · **deps:** SP-301–SP-306  
  - **AC:** VoiceOver labels on Hold/Reset/Start

- [ ] **SP-310** Dark shop-floor visual polish (large hit targets, arm’s-length readability)  
  - **Role:** UI · **deps:** SP-300 · **// parallel-ok** late  
  - **AC:** Consistent dark theme tokens

---

## Phase 4 — Machine features (router-focused)

- [ ] **SP-400** Work coordinate zero X/Y/Z (G10 vs G92 policy in profile + docs)  
  - **Role:** Core+UI · **deps:** SP-108, SP-306  
  - **AC:** Zero buttons send documented commands

- [ ] **SP-401** Soft-limit warnings when jog would exceed profile travel  
  - **Role:** Core+UI · **deps:** SP-100, SP-306  
  - **AC:** Warning UI when out of range

- [ ] **SP-402** Manual spindle UI (M3/M5 + S) — gated, never on connect  
  - **Role:** UI · **deps:** SP-108  
  - **AC:** Requires explicit user action

- [ ] **SP-403** Feed override display if firmware reports; optional overrides only if dialect-safe  
  - **Role:** Core+UI · **deps:** SP-103  
  - **AC:** Displays Ov fields when present

- [ ] **SP-404** Alarm recovery UX: common ALARM explanations; clear required before stream  
  - **Role:** UI · **deps:** SP-103, SP-301  
  - **AC:** Cannot Start while Alarm without clear path

- [ ] **SP-405** Research: FluidNC vs GRBL → `research/controller-matrix.md` + dialect flag  
  - **Role:** Tech writer · **deps:** none · **// parallel-ok**  
  - **AC:** Matrix file exists with baud/status notes

---

## Phase 5 — Hardening & packaging

- [ ] **SP-500** Stress: 10k+ line fixture on simulator without UI freeze  
  - **Role:** QA · **deps:** SP-202, SP-305  
  - **AC:** Main thread remains responsive (manual or automated probe)

- [ ] **SP-501** Logging levels; optional file log in Application Support  
  - **Role:** Core · **deps:** SP-108  
  - **AC:** Toggle or default info-level console

- [ ] **SP-502** Terminate: best-effort hold/close port  
  - **Role:** Core · **deps:** SP-204, SP-108  
  - **AC:** Documented lifecycle hooks

- [ ] **SP-503** End-user README expansion: cable, baud, simulator first, hardware checklist  
  - **Role:** Tech writer · **deps:** SP-302, SP-305  
  - **AC:** New operator can follow without agent

- [ ] **SP-504** Distribution runbook `docs/planning/DISTRIBUTION.md` (archive/notarize later)  
  - **Role:** Tech writer · **deps:** SP-000  
  - **AC:** Steps listed even if notarization is `[!]`

- [ ] **SP-505** MVP acceptance: AGENTS.md §6 all green on simulator  
  - **Role:** QA · **deps:** Phases 0–4 critical path  
  - **AC:** Checklist signed off in Work log

- [ ] **SP-506** `[!]` Live hardware session with user’s CNC router  
  - **Role:** Human+QA · **deps:** SP-505  
  - **AC:** Human confirms safe first air-cut job

---

## Phase 5b — Market pain: machine handoff (from competitor research)

> Full PAIN board: [`HERMES_STUDIO_TODO.md`](./HERMES_STUDIO_TODO.md) Wave **PAIN**. These Control tasks close **cluster 7** (fragmented machine handoff).

- [ ] **SP-510** Pre-flight checklist UI before Run (air-cut, XY/Z zero, tool, hold-downs, spindle) — **PAIN-703**  
  - **Role:** UI · **deps:** SP-305 · **AC:** Checklist must complete or pro-skip pref
- [ ] **SP-511** Post/format label clarity in save + run (`.nc` / `.gcode` per profile) — **PAIN-704**  
  - **Role:** Core · **deps:** SP-000 · **// parallel-ok**  
  - **AC:** User always sees controller-facing filename/extension
- [ ] **SP-512** One-click **Run** primary CTA after connect + zero + armed — **PAIN-705**  
  - **Role:** UI · **deps:** SP-510 · **AC:** Single obvious run control; Hold/Reset remain visible
- [ ] **SP-513** Host-native USB path docs (native Mac — no VM required) — **PAIN-103**  
  - **Role:** Tech writer · **deps:** SP-204 · **AC:** README section “Mac native serial”
- [ ] **SP-514** Integration hook for Studio “Run on machine” handoff — **PAIN-701**  
  - **Role:** Core · **deps:** SP-305 · **AC:** API or file drop contract documented for STU-210

---

## Phase 6 — Post-MVP backlog (do not start until SP-505)

- [ ] **SP-600** Char-count streaming mode for higher throughput  
- [ ] **SP-601** Probing wizard (G38.x)  
- [ ] **SP-602** Tool length / G54–G59 manager  
- [ ] **SP-603** Webcam spoilboard overlay (AVFoundation)  
- [ ] **SP-604** Multi-file job queue  
- [ ] **SP-605** Basic DXF → contour G-code (still not full CAM)  
- [ ] **SP-606** Network bridges (ESP3D / websocket)  
- [ ] **SP-607** SculptCast / shop drop-folder hooks  
- [ ] **SP-608** App Store / notarized public release  

---

## Work log

### 2026-07-28 — plan session (Grok)
- Created project folder `~/Desktop/ShopPilot`
- Wrote AGENTS.md, HERMES_BUILD_TODO.md, README.md, PRODUCT_BRIEF.md, SAFETY.md
- Scaffold dirs: Sources, Tests, fixtures/gcode, scripts, research, docs/planning
- **Next for Hermes:** Claim SP-000 and execute Wave 0

### 2026-07-28 — market pain items
- Added Phase 5b **SP-510…SP-514** (preflight, format clarity, one-click run, native serial docs, Studio handoff)
- Full complaint board: `HERMES_STUDIO_TODO.md` Wave PAIN + Wave DOC

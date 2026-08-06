# ShopPilot Pull Request

## SPK Card & Phase

| Field | Value |
| --- | --- |
| **SPK card** | (e.g. `SPK-0006`) |
| **Phase** | (A–K — which MASTER_KANBAN phase does this address?) |
| **Track** | A (Machine Control) / B (Studio/CAM) / Both |

> Briefly describe what this PR implements and which SPK card it fulfils.

---

## Design Rules Checklist

- [ ] **≤ 12 primary icons per stage** — no stage rail exceeds 12 visible icon buttons before overflow/⌘K
- [ ] **Progressive disclosure** — features reachable via stage, overflow menu, recipe, or ⌘K; no permanent icon walls
- [ ] **SwiftUI only** — no AppKit/UIKit bridging unless explicitly approved

---

## Safety Review Checklist

> All items must be checked before merging. If any safety item is N/A, mark it as such with a reason.

- [ ] **No third-party proprietary assets** — no CRV files, no third-party UI mockups, no reverse-engineered graphics or resource bundles
- [ ] **SAFETY.md compliance** — reviewed [`docs/planning/SAFETY.md`](../docs/planning/SAFETY.md); this PR does not violate any required product behaviour
- [ ] **E-stop / Reset visibility** — if machine-connected UI is touched, emergency controls remain always-visible in fixed chrome (not buried in menus)
- [ ] **No auto-start streaming** — file open never triggers G-code stream; explicit Start required after user review
- [ ] **No auto-connect on launch** — app does not connect to a port or run a job at startup
- [ ] **Spindle / coolant safety** — no accidental M3/M7 enable as a side effect of connection or UI navigation
- [ ] **Disconnect handling** — port errors stop stream and surface an alarm; no silent mid-job reconnect

---

## Testing

- [ ] Unit tests added / updated (if applicable)
- [ ] Simulator path verified (for machine-control changes)
- [ ] Xcode builds without new fatal warnings or errors introduced by this PR

---

## Screenshots / Recordings (UI changes)

<!-- Attach before/after screenshots or a short screen recording for any UI modification. -->

---

## Notes for Reviewers

<!-- Any context, trade-offs, or follow-up items worth flagging. -->

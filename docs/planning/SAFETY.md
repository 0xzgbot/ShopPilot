# ShopPilot — Safety Policy

> **⚠️ CNC routers are dangerous machines. ShopPilot is a tool, not a substitute for safe practices.**
>
> **Software controls are not a substitute for a hardware emergency stop.**

## Required product behaviors

1. Feed Hold and Reset always visible while connected.
2. No streaming until explicit Start after file load/review.
3. Port errors stop the stream and surface an error; no silent mid-job reconnect.
4. No spindle/coolant enable as a side effect of connect.
5. No auto-connect + auto-run on application launch.
6. Console can show raw TX/RX for diagnosis.
7. Soft-limit warnings when profile travel is configured.
8. In-app and README disclaimer about hardware e-stop.
9. Dirty-flag protection: cannot export G-code from unrecalculated toolpaths.
10. Preflight checklist required before Run.

## Safety documentation

- **README.md** — Scope disclaimer + safety warning in repo root.
- **PRODUCT_BOUNDARIES.md** — Honest scope: relief CAM, not full 3D CAD.
- **SHOPPILOT_SCOPE.md** — Full scope statement with safety section.
- **SAFETY.md** — This file: product behaviors + operator checklist.

## Testing bar before “live serial done”

- Unit tests for status parser and streamer state machine green.
- Simulator path exercises hold/resume/fault.
- Real hardware only after MVP acceptance on simulator (`SP-505` then `SP-506`).

## Operator checklist (hardware)

- [ ] Hardware e-stop within reach and tested
- [ ] Correct work zero and tool length
- [ ] Soft limits / travel match physical machine
- [ ] First moves are air cuts above the workpiece
- [ ] Spindle RPM and feeds verified for tool/material
- [ ] Safety glasses, hearing protection, no loose clothing
- [ ] Never leave running machine unattended

## Safety disclaimer (in-app)

All users must see this message before first hardware connection:

> **ShopPilot is a CNC toolpath generator and machine controller. It does not replace hardware safety. Always use a hardware emergency stop, wear appropriate PPE, and never leave a running machine unattended. Software controls, Preview heightfield, and the built-in simulator are not a substitute for a hardware e-stop or a proven live cut.**

See [`SHOPPILOT_SCOPE.md`](./SHOPPILOT_SCOPE.md) for the full scope and safety statement.

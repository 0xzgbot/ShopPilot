# ShopPilot — Safety Policy

**Software is not a substitute for a hardware emergency stop.**

## Required product behaviors

1. Feed Hold and Reset always visible while connected.
2. No streaming until explicit Start after file load/review.
3. Port errors stop the stream and surface an error; no silent mid-job reconnect.
4. No spindle/coolant enable as a side effect of connect.
5. No auto-connect + auto-run on application launch.
6. Console can show raw TX/RX for diagnosis.
7. Soft-limit warnings when profile travel is configured.
8. In-app and README disclaimer about hardware e-stop.

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

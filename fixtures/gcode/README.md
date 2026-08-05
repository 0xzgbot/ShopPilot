# G-code fixtures

Sample jobs for **simulator** development, UI path preview, and the verify suite.

> ⚠️ **SIM ONLY** — treat every file as simulation input until a human verifies travel limits on a real router. Prefer air moves (positive Z) for first hardware tests. Do not assume these match any particular machine envelope.

| File | Purpose |
| --- | --- |
| `square_air_10mm.nc` | Short closed path for streamer smoke tests |
| `rapid_only.nc` | Rapids only (no cutting moves) |
| `calibration_square.nc` | **Expected** calibration square — not yet committed (app falls back to the built-in 11-line air-cut square when absent; see `AppSession.loadFixtureGCodeIfNeeded`) |

## How fixtures are used

- The **Machine stage** auto-loads `fixtures/gcode/calibration_square.nc` when the session buffer is empty; if missing, it falls back to a built-in **air-cut square** (11 lines, G1 moves above stock) so the simulator always has something safe to stream.
- `scripts/verify_import_torture.py` and the `ShopPilotVerify*` CLTs reference fixture files for import/export and streamer tests.

## Adding a fixture

1. Keep it **air-cut safe**: positive Z rapids, no spindle-down paths without clear naming.
2. Name it by purpose (`long_stress_10k.nc`, `two_tool_vcarve.nc`, …).
3. Reference it from the relevant test/verify target.
4. Never point default demos at destructive spindle-down paths.

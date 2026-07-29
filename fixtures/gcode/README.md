# G-code fixtures

Sample jobs for **simulator** development and UI path preview.

- Treat all files as **SIM ONLY** until a human verifies travel limits on a real router.
- Prefer air moves (positive Z) for first hardware tests.
- Do not assume these match any particular machine envelope.

| File | Purpose |
| --- | --- |
| `square_air_10mm.nc` | Short closed path for streamer smoke tests |
| `rapid_only.nc` | Rapids only |
| (add later) | Long-line stress for SP-500 |

Agents: add new fixtures here and reference them from tests; never point default demos at destructive spindle-down paths without clear naming.

# Contract goldens — `.shoppilot` parity fixtures (SPK-1920i)

> **Purpose:** machine-checkable cross-platform contract for the `.shoppilot`
> document package. The three fixtures under [`fixtures/parity/`](../../fixtures/parity/)
> were saved by ShopPilot (macOS Swift) with `DocumentSaver`, reopened with
> `DocumentLoader` and asserted by `ShopPilotVerify1920i` (`PASS — 3 fixtures
> reopened`). VectorPilot (Windows C#) must reproduce the same open + assert
> behavior against these exact files.
>
> Saved: 2026-08-25 · Format version declared in each `manifest.json`: **0.2**
> (+ additive optional `relief.json`, see below)

---

## Fixtures

| Fixture | Job | Contents |
| --- | --- | --- |
| `fixtures/parity/sign_golden.shoppilot` | Sign — V-Carve Greeting (`SampleProjectsStore` sign sample, stable id `11111111-1111-1111-1111-111111111111`) | 20 vectors on one layer (borders, medallion gear, star, letters H-E-L-L-O, banner), sheet 450×300×18 mm, no toolpaths |
| `fixtures/parity/plaque_golden.shoppilot` | Plaque — Text Relief (`SampleProjectsStore` plaque sample + authored extras) | 16 vectors, ACTIVE relief heightfield (cameo grid), 1 relief component ("Cameo Dome", combine add, heightScale 1.25, 12×9 dome grid), Rough3D + Finish3D ops with params JSON + hand-written golden G-code |
| `fixtures/parity/inlay_golden.shoppilot` | Inlay — Two Wood (programmatic job) | 1 closed rectangle motif vector, two ops: **Inlay Pocket** (V-carve flat-bottom female) + **Inlay Plug** (profile male), full `InlayToolpathParams` JSON |

## Package layout (format v0.2 + SPK-1920i extension)

```
<name>.shoppilot/            ← directory bundle
├── manifest.json            ← job id/name/dates/version/documentVariables
├── toolpaths.json           ← [PersistedToolpath] (pretty-printed, sorted keys)
├── sheets/<sheet-id>.json   ← one file per Sheet incl. layers+vectors
└── relief.json              ← OPTIONAL (SPK-1920i): {stlHeightfield, reliefComponents}
```

**`relief.json` is additive + legacy-safe:** written only when the document
carries relief data; packages without it decode unchanged; readers that do
not know the file ignore it. Older Mac builds opening these fixtures still
open fine (relief section skipped). **VectorPilot MUST read `relief.json`.**

## SHA-256 hashes

Byte-stable contract files (deterministic ids + sorted-key encoders):

```
8a0ae2fb397ad1bd53f8f1727d341976dc51a91a1b7630337c988787347148e8  fixtures/parity/sign_golden.shoppilot/sheets/13111111-1111-1111-1111-111111111111.json
ace810d7e2cbb4f8c40ce09dc8e191ae466adb4e1a7d49c59f2215b411d38b05  fixtures/parity/sign_golden.shoppilot/toolpaths.json
d64f29dac48ab9f495c162c95b1b29e074eb4fec2bbfa4d2b90dca79a1128117  fixtures/parity/plaque_golden.shoppilot/sheets/46444444-4444-4444-4444-444444444444.json
9163aad6ce1faf35937dd8b34688d8f58b0a3f0989f2768f0226a76b7185eb65  fixtures/parity/plaque_golden.shoppilot/toolpaths.json
d39837af398897216f386d6a1b06bb7ef392d983487546485086f70bc4f70ded  fixtures/parity/plaque_golden.shoppilot/relief.json
12098befa009b1475db995683fb191ce483db53182fb063273af98b39d87df8f  fixtures/parity/inlay_golden.shoppilot/sheets/19201920-AAAA-BBBB-CCCC-DDDDEEEEFFFF.json
ef0d353d1e229d87f2e827ad722eacb83bfe690b32630130e94327d23d49ac0d  fixtures/parity/inlay_golden.shoppilot/toolpaths.json
```

**Not hash-compared:** `manifest.json` files (contain wall-clock
`createdAt`/`updatedAt`; compare by STRUCTURE — keys `id`, `name`,
`createdAt`, `updatedAt`, `version` `"0.2"`, `sheetCount`,
`documentVariables` — not bytes). Fixture manifests:

```
b11a5e2a13164812292d849bd28ea91af8911b3775c06784ca5c7e929e2ab4b8  fixtures/parity/sign_golden.shoppilot/manifest.json      (reference only)
d7748caacc8f321426682beba734962e5e55b0f7fd72a275a21d2bf40f90bd28  fixtures/parity/plaque_golden.shoppilot/manifest.json    (reference only)
0e0db7ca3ecb18ad73e1cd3b74b0c237d612e699da1a7c70e0a791812b13fc71  fixtures/parity/inlay_golden.shoppilot/manifest.json     (reference only)
```

## What VectorPilot must verify

For **each** fixture: open the package, decode every file, and assert:

### All three fixtures
- Manifest decodes; `version == "0.2"`; `id` matches the sheet-file layer linkage.
- Sheet JSON decodes to stock dims + ordered layers with vectors:
  - Sign sheet: `450 × 300 × 18` mm.
  - Vector order, names, point lists (mm, exact), `isClosed` flags match the
    Mac asserts (sign: 20 paths incl. "Outer Outline", "Medallion",
    "Letter O", "Banner"; plaque: 16 paths; inlay: single closed
    "Inlay Motif" rectangle 20,20→80,60).
- `toolpaths.json` decodes as an array of `{id, name, toolpathResult,
  estimatedTimeSeconds, isDirty, toolID, paramsJSON, isEnabled}`; missing
  trailing optionals decode as null/default (legacy-safe rule).

### Plaque fixture (3D)
- `relief.json` decodes: ACTIVE `stlHeightfield` grid **verbatim**
  (width×height cells, `cellSizeMm`, origin `minX/minY`, full heights array),
  plus `reliefComponents[0]`: name "Cameo Dome", combine mode `combineAdd`,
  visible true, `heightScale 1.25`, its own 12×9 dome grid intact.
- Two ops named "Rough 3D — Plaque" and "Finish 3D — Plaque";
  `toolpathResult` G-code text matches the committed files exactly;
  decoded rough params: Ø6.35 / stepdown 1.8 / feed 900 / allowance 0.4 /
  18000 rpm; finish params: stepover 0.35 / 21000 rpm.

### Inlay fixture (pocket + plug)
- Two ops decode `InlayToolpathParams` from `paramsJSON`:
  - Pocket: `variant "pocket"`, depth 2.4 mm, V-bit 60°, safe Z 3,
    feed 800, plunge 150, Ø3.175, 24000 rpm.
  - Plug: `variant "plug"`, same depth/angle/safeZ, feed 700, plunge 140.
- Physics contract these numbers pin (mirrors SPK-2021a): pocket is the
  flat-bottom V-carve female half, plug is the profile "on" male half at the
  SAME inlay depth and V-bit angle.

## Regenerating / re-verifying on Mac

```bash
./scripts/verify_locked.sh ShopPilotVerify1920i          # rebuilds fixtures + reopen asserts
shasum -a 256 $(find fixtures/parity -type f | sort)     # refresh this table if fixtures change
```

The CLT prints `ShopPilotVerify1920i: PASS — 3 fixtures reopened`.
Fixtures are regenerated deterministically except for manifest dates.

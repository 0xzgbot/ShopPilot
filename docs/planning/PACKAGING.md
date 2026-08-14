# ShopPilot packaging (personal use)

**Version:** 0.06  
**Last updated:** 2026-08-13

This is **not** a paid-tier / App Store plan. ShopPilot is personal-use only; notarization and public distribution cards are `[-]` on `MASTER_KANBAN.md`.

---

## What `scripts/package_app.sh` does

1. Release-builds **x86_64** and **arm64** via `./scripts/swift_locked.sh` (never a second `swift` while one holds the lock).
2. `lipo` → universal `ShopPilot.app/Contents/MacOS/ShopPilot`.
3. Writes `Info.plist` with `CFBundleShortVersionString` = `$VERSION` (default: `git describe --tags --always`, often a commit hash — **pass VERSION explicitly**).
4. Copies `fixtures/` and `dist/icon-src/ShopPilot.icns` into Resources.
5. Ad-hoc `codesign --sign -`.
6. Zips with `ditto` to `dist/$ZIP_NAME` (default `ShopPilot-macOS.zip`).

Match the committed 0.06 artifact:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
VERSION=0.06 ZIP_NAME=ShopPilot-0.06-macOS.zip ./scripts/package_app.sh
```

Output: `dist/ShopPilot-0.06-macOS.zip` — universal, ad-hoc signed. Gatekeeper: right-click → Open, or `xattr -dr com.apple.quarantine ShopPilot.app`.

The unpacked `.app` is not the source of truth; rebuild the zip from source.

---

## Requirements

- macOS 14+
- Xcode 15+ (`DEVELOPER_DIR` pointing at Xcode.app, not Command Line Tools alone)
- Apple Silicon and Intel both produced; one zip

**Out of this script:** Apple Developer notarization, stapling, Mac App Store, Sparkle.

---

## Product surface (honest)

Personal CNC: 2D design, Profile/Pocket/Drill/V-Carve, 3D rough/finish from heightfields, 2.5D Preview, simulator + optional GRBL serial.

**Not packaged as products:** laser / LightBurn, Fusion-style 3D CAD, paid Core/Studio/Studio3D unlocks (legacy notes below this line are obsolete).

---

## Laser

**Held.** Engine goldens may exist historically; there is no laser product UI. Do not expand laser in packaging copy.

---

## References

- Root [`README.md`](../../README.md)
- [`SAFETY.md`](SAFETY.md)
- [`MASTER_KANBAN.md`](../../MASTER_KANBAN.md) — SPK-0623 owner-gated; SPK-0621/0622 `[-]`

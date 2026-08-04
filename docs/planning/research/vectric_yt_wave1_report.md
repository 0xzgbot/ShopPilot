# Vectric YouTube Wave-1 Research Report

**Date:** 2026-08-04 · **Agent:** ShopPilot research (transcripts only) · **Scope:** Vectric Ltd channel, V12/V12.5 tutorials, lean CNC filter

## Counts

| Metric | Value |
|---|---|
| Channel videos cataloged (flat playlist) | 1,388 |
| Playlist entries fetched (V12/V12.5 "How to" playlists) | 122 |
| Catalog rows total (deduped by video_id) | 1,389 |
| **Wave-1 include** | **67** |
| Wave-2 (defer) | 756 |
| Skip (marketing/laser/cabinet/rotary/cloud/dupes) | 566 |
| Captions fetched (Wave-1) | **67 / 67** |
| Captions missing | 0 |
| Caption quality | auto (67) — no manual tracks found |
| Media downloaded | **0** (subs-only, `--skip-download`) |

Raw captions: `research/raw/vectric_yt_captions/*.txt` (gitignored). Catalog:
`docs/planning/research/vectric_yt_catalog.csv` (includes `caption_status`).

## Top 30 features by mention (across 67 Wave-1 transcripts)

| # | Feature | Mentions | Category |
|---|---|---|---|
| 1 | toolpath preview / simulation | 44 | preview |
| 2 | material/sheet-aware preview | 26 | preview |
| 3 | job setup / material size | 22 | job_setup |
| 4 | material thickness & z-zero | 22 | job_setup |
| 5 | align/mirror/rotate objects | 21 | design_2d |
| 6 | layer preview (per-toolpath) | 21 | preview |
| 7 | 3D component / relief model | 19 | model_3d |
| 8 | 3D import (STL/3DS/etc) | 18 | model_3d |
| 9 | text tool / lettering | 17 | design_2d |
| 10 | node editing | 17 | design_2d |
| 11 | layers | 17 | design_2d |
| 12 | combine modes (add/subtract/merge) | 17 | model_3d |
| 13 | ramp / lead-in | 17 | toolpath_shared |
| 14 | vector draw tools (rect/circle/arc/polyline) | 15 | design_2d |
| 15 | tool database | 14 | job_setup |
| 16 | save/export G-code | 14 | post_output |
| 17 | V-Carve toolpath | 13 | vcarve |
| 18 | component tree | 12 | model_3d |
| 19 | tabs | 12 | toolpath_shared |
| 20 | vector offset | 11 | design_2d |
| 21 | start depth / max depth | 11 | vcarve |
| 22 | machine configuration (posts/dialect) | 9 | job_setup |
| 23 | vector boundary | 9 | design_2d |
| 24 | V-bit / engraving bit | 9 | vcarve |
| 25 | carved/dished recess | 9 | model_3d |
| 26 | 3D finishing toolpath | 9 | toolpath_shared |
| 27 | post processor selection | 9 | post_output |
| 28 | flat depth | 8 | vcarve |
| 29 | toolpath recalculate | 8 | toolpath_shared |
| 30 | snapping | 8 | other |

Full table with example_video_ids and lean_relevance: `LEAN_YT_FEATURE_MENTIONS.csv`.

## 10 most important gotchas (from transcript reading)

1. V-Carve depth is emergent (tool angle × vector width) — no cut-depth field; wide areas
   punch through material unless **flat depth** caps it.
2. V-Carving requires **closed vectors** — enforced with an error, not a warning.
3. **Recalculate is explicit and mandatory** after vector edits; stale toolpaths silently
   cut wrong geometry.
4. **Material thickness must be measured** (calipers); 0.5″ vs 0.455″ example; drives cutout
   depth + preview fidelity.
5. **Zero off the surface you carve into** — Z-zero mode is the machine contract.
6. Grayed-out tool in DB = missing feeds/speeds for that material+machine — must be added
   before toolpath creation (or at creation time).
7. Profile cutout destroys the chamfer unless you offset by the chamfer width (allowance
   offset).
8. No tabs + no vacuum = part **flies out on the last pass**.
9. Single-file save fails across different tools unless the post supports ATC tool changing.
10. Multi-file save respects toolpath order — filenames encode cut order; reorder by
    dragging before saving.

## Wave-2 backlog (756 rows, ready to run)

The biggest Wave-2 buckets (catalog `skip_reason` / playlist tags): V11/V10/V9-era duplicate
"How to" series (same concepts, older UI), toolpath deep-dives deferred (chamfer, fluting,
moulding, prism, texture toolpath, sketch carve, V-Carve inlay, tiling 2D/3D, sheets,
nesting), model-region/text-region/guides videos, and legacy training-series letters
(B0x/C0x/G0x). Wave-2 is only worth running if Wave-1 evidence feels thin on a specific
capability — the feature list already saturates.

## Work log

Fetched the Vectric Ltd channel flat playlist (1,388 videos) + 14 V12/V12.5 playlists (122
videos), merged and deduped by video_id into the catalog CSV with rule-based Wave-1/2/skip
classification plus an explicit override list (legacy-series dupes, v3 marketing, promo
shorts, V12/V12.5 duplicates → wave2/skip). Fetched captions for all 67 Wave-1 videos with
`yt-dlp --skip-download --write-auto-sub` (VTT → plain text with header; caption_quality=auto
for all — Vectric ships no manual tracks), rate-limited 1.5 s between videos, 3 retries;
0 missing, 0 media files. Deduplicated the VTT triple-line artifact. Ran a keyword feature
pass over all 67 transcripts → `LEAN_YT_FEATURE_MENTIONS.csv` + per-video extraction stubs.
Read 18 cornerstone transcripts in full (Getting Started series, V-Carve/clearance,
3D rough/finish, material/machine/tool DB, preview, save, validator, recalc) and enriched
their `extractions/*.md` with real workflow steps, parameters, gotchas, and notes. Wrote
`WHAT_IT_TAKES_CNC_APP.md` (workflow, must-haves, 3D path, V-Carve path, failure modes,
non-goals, blind spots flagged UNVERIFIED vs codebase).

**Blockers:** none. The Aspire tutorials index page (vectric.com) is JS-rendered and yielded
no video list, so the YouTube channel dump was used as the source of truth. Video duration for
a few standalone rows is blank (flat playlist quirk). All captions are auto-quality; content
is occasionally repetitive but usable.

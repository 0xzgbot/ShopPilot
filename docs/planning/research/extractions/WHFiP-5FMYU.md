# Extraction: WHFiP-5FMYU (enriched)

## capabilities_mentioned
- edit toolpath (double-click or right-click)
- duplicate toolpath
- delete toolpath (this/invisible/visible/all)
- recalculate (selected/visible/all)
- dirty toolpaths after vector edits
- recalculate-all button
- success confirmation

## workflow_steps
1. Edit: double-click or right-click toolpath -> edit -> change depth/settings -> CALCULATE again to apply -> Duplicate: right-click -> duplicate -> Delete: right-click -> delete this/invisible/visible/all -> Recalculate: right-click -> recalculate selected/visible/all OR toolbar recalc-all -> confirm success popup

## parameters_concepts
- cut depth
- recalculate granularity (selected/visible/all)

## gotchas_warnings
- After editing VECTORS, existing toolpaths are stale — MUST recalculate
- Calculate is the explicit 'apply' step; editing settings alone does nothing
- Recalc-all with success confirmation = the dirty-toolpath UX pattern

## lean_relevance
**must**

## notes
The dirty/recalculate contract: vector edits invalidate toolpaths; recalc is explicit and granular. ShopPilot already has dirty/recalc in scope (LEAN_CNC_SCOPE P0) — this confirms the UX.

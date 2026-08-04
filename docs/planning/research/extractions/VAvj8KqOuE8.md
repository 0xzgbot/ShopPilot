# Extraction: VAvj8KqOuE8 (enriched)

## capabilities_mentioned
- profile toolpath (cut around/along vectors)
- start depth / cut depth
- z= material-thickness shortcut
- tool selection + per-toolpath edit (non-destructive to DB)
- pass depth (multi-pass)
- cut side: inside/outside/on-line
- climb vs conventional
- ramp plunge moves
- tabs (constant number / constant distance, avoid corners/curves, manual placement)
- toolpath naming + calculate + preview

## workflow_steps
1. Select vector -> profile toolpath -> start depth (0 = surface; set if cutting into pocket) -> cut depth (z= fills material thickness) -> select tool (edit per-toolpath is non-destructive to DB defaults) -> pass depth (0.125 steps to 0.5 total) -> machine on inside/outside/on-line -> direction climb/conventional -> optional ramp plunge (length e.g. 1") -> optional tabs (auto count or spacing, avoid corners/curved regions, manual drag) -> name -> calculate -> preview (double-click waste to remove)

## parameters_concepts
- start depth
- cut depth
- pass depth (per-pass Z)
- cut side
- climb/conventional
- ramp length
- tab length/thickness/count/spacing
- plunge behavior

## gotchas_warnings
- Multi-pass profile: pass depth controls Z steps; too deep = tool stress
- Ramp plunge avoids vertical plunge stress, enables faster plunge
- No vacuum hold-down -> part flies out on last pass -> use tabs
- Tabs on corners/curves are hard to remove — avoid
- Per-toolpath tool edit doesn't overwrite tool DB defaults

## lean_relevance
**must**

## notes
The profile toolpath reference — multi-pass, ramping, tabs, side selection. Tabs + ramp are the two machine-safety features tutors treat as default-on for cutouts.

# Extraction: NF9oaCjXmAo (enriched)

## capabilities_mentioned
- 3D finishing toolpath
- ball-nose tool selection (1/8"), multiple tools
- machining boundary limit
- boundary offset = tool diameter
- rest machining (smaller bit cleanup)
- strategy: offset (inside-out) vs raster
- climb/conventional cut direction
- stepover retract
- raster angle
- machining allowance removal
- per-tool strategy selection
- minimum detail (rest machining)

## workflow_steps
1. Create roughing first (Z-level, boundary offset = rough cutter dia, allowance 0.04) -> open 3D finishing toolpath -> choose ball-nose (1/8") -> boundary limit matching roughing -> boundary offset = finish tool diameter (0.125) -> strategy offset (inside-out) or raster -> set stepover + optional stepover retract (0.025) to hide witness marks -> optional rest machining: add smaller bit (1/16") with minimum-detail slider -> calculate -> preview (roughing + finishing results combined/subtract)

## parameters_concepts
- ball-nose size
- boundary offset = tool dia
- machining allowance (0.04)
- stepover
- stepover retract (0.025)
- raster angle
- climb/conventional
- rest-machining minimum detail

## gotchas_warnings
- Finish removes the roughing allowance to reveal detail
- Boundary offset = finish tool diameter reduces cusping at edges
- Stepover retract hides witness marks from spiral loops (but not software-visible)
- Rest machining = bigger bit then smaller bit for fine detail; per-tool strategy selectable
- Roughing+finishing previews can be combined in one preview to verify

## lean_relevance
**must**

## notes
The 3D finishing spine. Ball-nose + stepover + offset/raster strategies; rest machining for detail. Directly informs ShopPilot's 3D finish pass (SPK lean 3D).

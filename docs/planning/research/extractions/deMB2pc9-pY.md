# Extraction: deMB2pc9-pY (enriched)

## capabilities_mentioned
- V-Carve toolpath with clearance tool
- clearance tool = end mill that pre-removes bulk material
- offset toolpath strategy for clearance
- drill toolpath (plunge at vector center)
- chamfer toolpath (bevel width param)
- profile cutout with allowance offset
- tabs (auto placement)
- toolpath reorder by drag
- save visible toolpaths grouped to one file
- bitmap trace (black/white)
- layers with colors
- mirror/align/offset layout tools

## workflow_steps
1. Job setup (single-sided, size, thickness, units, datum, Z-zero) -> import bitmap -> bitmap trace to closed vectors -> delete bitmap -> organize layers -> draw ellipse + offset border -> draw/mirror drill-hole circles -> align text group -> V-Carve (finish V-bit + clearance end mill, flat depth) -> drill toolpath -> chamfer toolpath -> profile cutout with allowance offset to preserve chamfer -> reorder toolpaths to group same-bit ops -> save visible toolpaths with correct machine+post

## parameters_concepts
- flat depth
- start depth
- chamfer width (0.15 here)
- allowance offset = chamfer width
- tab length/thickness
- material thickness measured with calipers (0.455)
- clearance tool = 1/4" end mill, finish = 60° V-bit

## gotchas_warnings
- Clearance tool = 1/4" end mill + offset strategy; V-bit sharpens corners after
- Drill toolpath plunges at vector CENTER — vector diameter is irrelevant
- Profile cutout must offset by the chamfer width or it cuts the chamfer off
- Check material thickness with calipers — estimate was wrong (0.5 vs 0.455)
- Group toolpaths by tool to minimize tool changes; save order = cut order
- Tabs keep part in place for final cutout

## lean_relevance
**must**

## notes
The canonical multi-toolpath sign workflow. Shows the full chain: trace -> V-carve+clearance -> drill -> chamfer -> cutout with allowance -> reorder -> save grouped. Clearance tool is P0 for ShopPilot (LEAN_CNC_SCOPE).

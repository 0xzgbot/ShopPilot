# Extraction: ooTRI9rHydw (enriched)

## capabilities_mentioned
- Job setup form
- rectangle tool with corner radius handles
- offset with sharp corners
- text + font/bold
- convert text to curves
- group/ungroup
- mirror copy (horizontal+vertical)
- pocket toolpath
- profile cutout with tabs
- material setup (rapid Z gap, plunge gap, home position)
- save visible toolpaths to multiple files
- 3D preview + waste deletion
- alignment tools

## workflow_steps
1. Create file (11x6x0.75) -> draw rectangle -> set exact size via edit box -> align center -> radius corners (-0.75) -> offset inward 0.325 sharp corners -> add text (Candera bold) -> convert text to curves -> group per line -> scale/position -> add mounting circles (0.125 dia = tool dia) -> mirror copies to 4 corners -> material setup check (thickness 0.755, datum, Z-zero, rapid gaps) -> pocket toolpath (1/8" end mill, closed vectors) -> preview -> profile cutout (1/8" end mill, outside, z=thickness, 4 tabs 0.5x0.125) -> preview -> save visible toolpaths to multiple files (sign_1=pocket, sign_2=cutout)

## parameters_concepts
- material thickness
- rapid Z gap (safe traverse height)
- plunge gap
- home/start XY+Z
- pocket stepover/depth
- tab length 0.5 / thickness 0.125
- datum = bottom-left, Z-zero = material top

## gotchas_warnings
- ALWAYS check material setup before toolpaths — it tells software how material sits on machine
- Circle diameter for holes should be >= tool diameter or tool can't enter
- Preview in 3D before saving; errors show up there
- Save to multiple files names them project_1, project_2 = cut order
- Rectangle tool stays parametric only if you didn't break the vector — can re-edit radius later

## lean_relevance
**must**

## notes
The full first-project video. Emphasizes material setup as mandatory preflight, exact-size editing, tabs for cutout safety, and the 'multiple files' save that encodes cut order in the filename.

# Extraction: kdvjB-4ET7o (enriched)

## capabilities_mentioned
- DXF vector import
- proportional scaling via corner handle
- offset with rounded corners
- V-Carve toolpath (no flat depth)
- profile cutout toolpath
- text creation + font matching
- set object size (XY link off for one-axis)
- guidelines for text height
- measure tool
- node edit (cut/join)
- weld closed vectors
- polyline arrow drawing
- 3D preview with waste removal (double-click waste)

## workflow_steps
1. New file (single-sided, 12x5x0.75) -> import bulls-head DXF -> scale proportionally -> align center -> offset border outward (rounded corners) -> check material setup -> V-Carve center vectors (60° V-bit, no flat depth) -> profile cutout (1/4" end mill, outside, z= thickness) -> preview + double-click waste to inspect -> edit: replace text, match font, measure, guidelines, node-cut vector, join closed, offset text border, weld outlines -> add arrow -> re-toolpath

## parameters_concepts
- material thickness (z= shortcut in cut depth field)
- offset distance (0.25)
- text size via set-size with XY-link off
- start depth 0
- no flat depth (let V-bit run deep)

## gotchas_warnings
- 'z=' shortcut fills material thickness in cut depth
- Text with descenders (q) breaks naive height sizing — use guidelines
- Weld requires TWO CLOSED vectors — close open vectors first (node cut + join with line)
- Small leftover slivers will break off anyway — delete them
- After editing vectors, toolpaths MUST be recalculated

## lean_relevance
**must**

## notes
Shows the design-editing side: import -> edit vectors -> v-carve -> cutout, plus the 'replacement text' workflow with guidelines and measurement. Highlights that text is editable only while still text — convert to curves loses editability.

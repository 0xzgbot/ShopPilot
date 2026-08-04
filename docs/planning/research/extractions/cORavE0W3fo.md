# Extraction: cORavE0W3fo (enriched)

## capabilities_mentioned
- 3D composition assembly
- clip art / 3D component placement
- component scale/shape height/base height controls
- text on 3D component with curve handle
- sketch carving toolpath (2D approximation of 3D)
- line thickness tracing parameter
- V-Carve text on component
- toolpath groups (empty group, rename, drag members)
- model position in material
- very high modeling resolution

## workflow_steps
1. Create file (9x6x0.759, very high modeling resolution) -> place 3D components (plant, ribbon) -> scale/rotate/position -> add base height to fix layering (ribbon over petal) -> balance high points to use material thickness -> add text curved to ribbon -> material setup (thickness, model position top) -> Option A: sketch carving (V-bit, line thickness = detail) -> add V-Carve text -> group toolpaths -> Option B: proper 3D roughing + finishing

## parameters_concepts
- modeling resolution (very high for detail)
- component shape height / base height
- model position in material
- sketch-carve line thickness
- start depth / flat depth (sketch)

## gotchas_warnings
- Modeling resolution = pixel budget for 3D detail — very high for real carving
- Base height fixes component layering (raise ribbon over petal)
- Balance component high points against material thickness
- Sketch carving = fast 2D approximation of 3D content — a good cheap preview option

## lean_relevance
**must**

## notes
Two cutting styles for one 3D layout: sketch carve (fast V-bit 2D) vs true 3D rough+finish. Model position in material is a first-class setup field for 3D.

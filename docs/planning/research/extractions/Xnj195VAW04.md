# Extraction: Xnj195VAW04 (enriched)

## capabilities_mentioned
- toolpath preview (selected/all/all sides)
- material textures (built-in / custom photo)
- solid color material
- machine area color (material/surface/global fill/toolpath color)
- draw tool to scale
- animate preview
- preview speed slider
- reset preview
- material settings in preview
- lithophane preview (excluded)

## workflow_steps
1. Switch to toolpath tab -> activate toolpaths -> preview toolpath (play icon) -> toggle toolpaths visible -> set material (wood/metal/stone/plastic presets or custom texture photo, solid color) -> set machine area color mode (material color / surface color / global fill color / per-toolpath color) -> enable draw tool (to-scale tool) + animate -> adjust speed slider -> preview selected/all -> reset

## parameters_concepts
- material presets + custom texture
- surface color vs material color
- global fill color
- per-toolpath color
- preview speed
- draw tool scale

## gotchas_warnings
- Per-toolpath colors communicate cutting strategy to customers/clients
- Surface color mode models painted-then-carved finishes
- Animate + draw tool = check actual tool engagement
- Witness marks from stepover are machine-side, not preview-visible

## lean_relevance
**must**

## notes
Preview is a first-class deliverable in Vectric — not an afterthought. Material fidelity (textures, painted surfaces, per-path colors) sells the job before cutting. ShopPilot's sheet-aware preview (SPK-1103) maps to this.

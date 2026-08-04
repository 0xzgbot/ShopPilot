# Extraction: 5wOzzsZ870k (enriched)

## capabilities_mentioned
- 3D roughing toolpath
- tool selection (end mill)
- machining limit boundary (model/material/vectors/level)
- boundary offset
- machining allowance
- roughing strategy: Z-level vs 3D raster
- profile around levels (before/after/none)
- order: level-by-level vs depth-first
- raster angle
- ramp plunge moves
- avoid machined areas (raster)
- toolpath naming

## workflow_steps
1. Open 3D roughing toolpath -> choose cutter (end mill) from tool DB -> set machining limit boundary (model boundary typical; material/vector/level options) -> optional boundary offset (e.g. +0.25" so finish tool fits) -> set machining allowance left for finish (e.g. 0.04") -> choose strategy: Z-level (pocket per pass depth; profile per level before/after; level-by-level vs depth-first order) OR 3D raster (follows 3D profile; avoid-machined-areas option; raster angle) -> optional ramp plunge -> name -> calculate -> preview visible toolpath

## parameters_concepts
- machining boundary + offset
- machining allowance (0.04 example)
- pass depth
- raster angle
- strategy (Z-level / 3D raster)
- profile before/after level
- level-by-level vs depth-first
- ramp plunge

## gotchas_warnings
- Roughing exists because parts too deep/unsafe for finish tool in one pass
- Boundary offset = cutter diameter gives finish tool room to fit
- Z-level profiles around levels help brittle materials avoid chipping
- Raster 'avoid machined areas' may or may not speed up cutting — test

## lean_relevance
**must**

## notes
The 3D roughing spine. Two strategies: Z-level (pocket layers) and 3D raster (follow surface). Machining allowance + boundary offset are the key inter-toolpath contracts with the finish pass.
